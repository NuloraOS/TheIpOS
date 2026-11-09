import AVFoundation
import CoreImage
import Photos
import UIKit

enum CameraFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

final class CameraEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    struct Options { var horizon = false; var crop = CropMode.dynamic; var shape = FrameShape.portrait; var resolution = 720 }
    struct State {
        var ready = false, recording = false, finishing = false, ultraWide = false, torch = false, front = false, ultraSelected = false, motionAvailable = true
        var message = "Подготовка камеры…"
        var duration = 0.0
        var motionReady = false, tilt = 0.0, digitalZoom = 1.0
        var motionStatus = "Ожидание датчиков…"
        var resolution = 720
    }
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "camera.capture", qos: .userInitiated)
    private let deliveryQueue = DispatchQueue(label: "camera.samples", qos: .userInitiated)
    private let videoPermit = DispatchSemaphore(value: 1), audioPermit = DispatchSemaphore(value: 8)
    var onFrame: ((CIImage) -> Void)?
    var onState: ((State) -> Void)?
    var onSaved: ((URL) -> Void)?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let context = CameraGPU.context
    private let motion = MotionTracker()
    private var options = Options(), state = State()
    private var cameraInput: AVCaptureDeviceInput?
    private var recorder: MovieRecorder?
    private var configured = false, audioEnabled = false, starting = false
    private var generation = 0
    private var digitalZoom = 1.0
    private var zoom = 1.0, startedAt: Double?, lastStateTime = 0.0, lastMotionStatus = 0.0
    private var latestImage: CIImage?
    private var outputSize: CGSize { CGSize(width: options.shape.size.width * CGFloat(state.resolution) / 720, height: options.shape.size.height * CGFloat(state.resolution) / 720) }

    func start() {
        queue.async {
            guard !self.starting else { return }
            if self.session.isRunning { return }
            self.starting = true; self.generation += 1
            let ticket = self.generation
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--ui-probe") {
                self.starting = false; self.state.ready = true
                self.state.resolution = self.options.resolution
                self.state.message = "Симулятор · без камеры"; self.publish(); return
            }
            #endif
            Self.permission(.video) { allowed in
                guard allowed else { self.queue.async { guard ticket == self.generation else { return }; self.starting = false; self.state.message = "Разрешите доступ к камере в настройках iPhone"; self.publish() }; return }
                Self.permission(.audio) { microphone in self.queue.async {
                    guard ticket == self.generation else { return }
                    self.starting = false
                    do {
                        if !self.configured { try self.configure(microphone: microphone) }
                        if !self.session.isRunning { self.session.startRunning() }
                        if self.options.horizon { self.motion.start() }
                        self.state.ready = false; self.state.message = "\(self.state.resolution)p · " + (self.audioEnabled ? "до 30 кадров/с" : "без микрофона")
                        self.publish()
                    } catch { self.fail(error) }
                } }
            }
        }
    }

    private static func permission(_ type: AVMediaType, completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: completion(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: type, completionHandler: completion)
        default: completion(false)
        }
    }

    func setZoom(_ value: Double) {
        queue.async {
            self.digitalZoom = CameraZoom.clamp(value)
            self.state.digitalZoom = self.digitalZoom
            self.publish()
        }
    }

    private func configure(microphone: Bool) throws {
        session.beginConfiguration(); defer { session.commitConfiguration() }
        applyResolution()
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CameraFailure.message("Камера недоступна") }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input), session.canAddOutput(videoOutput) else { throw CameraFailure.message("Камеру не удалось настроить") }
        session.addInput(input); cameraInput = input
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: deliveryQueue); session.addOutput(videoOutput)
        if microphone, let mic = AVCaptureDevice.default(for: .audio), let audioInput = try? AVCaptureDeviceInput(device: mic), session.canAddInput(audioInput), session.canAddOutput(audioOutput) {
            session.addInput(audioInput); session.addOutput(audioOutput)
            audioOutput.setSampleBufferDelegate(self, queue: deliveryQueue); audioEnabled = true
        }
        if #available(iOS 13.0, *) { state.ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil }
        state.motionAvailable = motion.available
        if !motion.available { options.horizon = false }
        try configureDevice(camera); configureConnection(); configured = true
    }

    private func configureDevice(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        }
    }

    private func configureConnection() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
        if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false }
        // Native stabilization adds latency; do not combine it with gyro timestamps.
        if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = options.horizon ? .off : .auto }
    }

    func update(_ newOptions: Options) {
        queue.async {
            guard self.recorder == nil && !self.state.finishing else { return }
            let resolutionChanged = self.options.resolution != newOptions.resolution
            self.options = newOptions; self.options.horizon = newOptions.horizon && self.motion.available
            if resolutionChanged && self.configured { self.session.beginConfiguration(); self.applyResolution(); self.session.commitConfiguration() }
            self.zoom = 1; self.configureConnection()
            if self.options.horizon && self.session.isRunning { self.motion.start() } else { self.motion.stop() }
            if newOptions.horizon && !self.motion.available { self.state.message = "Датчики движения недоступны — обычный режим"; self.publish() }
        }
    }

    private func applyResolution() {
        let preset: AVCaptureSession.Preset = options.resolution >= 1080 ? .hd1920x1080 : .hd1280x720
        if session.canSetSessionPreset(preset) { session.sessionPreset = preset; state.resolution = options.resolution >= 1080 ? 1080 : 720 }
        else if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720; state.resolution = 720 }
    }

    func focus(at point: CGPoint) {
        queue.async {
            guard let device = self.cameraInput?.device else { return }
            do { try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                let p = CGPoint(x:min(1,max(0,point.x)),y:min(1,max(0,point.y)))
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = p; if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus } }
                if device.isExposurePointOfInterestSupported && device.exposureMode != .custom { device.exposurePointOfInterest = p }
            } catch { self.fail(error) }
        }
    }
    func setExposure(_ value: Float) {
        queue.async { guard let d = self.cameraInput?.device else { return }; do { try d.lockForConfiguration(); defer { d.unlockForConfiguration() }; d.setExposureTargetBias(min(d.maxExposureTargetBias,max(d.minExposureTargetBias,value)),completionHandler:nil) } catch { self.fail(error) } }
    }
    func setFocusDistance(_ value: Float) {
        queue.async { guard let d = self.cameraInput?.device, d.isFocusModeSupported(.locked) else { return }; do { try d.lockForConfiguration(); defer { d.unlockForConfiguration() }; d.setFocusModeLocked(lensPosition:min(1,max(0,value)),completionHandler:nil) } catch { self.fail(error) } }
    }
    func setManual(iso: Float?, seconds: Double?, temperature: Float?) {
        queue.async {
            guard let d = self.cameraInput?.device else { return }
            do { try d.lockForConfiguration(); defer { d.unlockForConfiguration() }
                if (iso != nil || seconds != nil) && d.isExposureModeSupported(.custom) {
                    let sensitivity = min(d.activeFormat.maxISO,max(d.activeFormat.minISO,iso ?? d.iso))
                    let duration = min(CMTimeGetSeconds(d.activeFormat.maxExposureDuration),max(CMTimeGetSeconds(d.activeFormat.minExposureDuration),seconds ?? CMTimeGetSeconds(d.exposureDuration)))
                    d.setExposureModeCustom(duration:CMTime(seconds:duration,preferredTimescale:1_000_000),iso:sensitivity,completionHandler:nil)
                }
                if let temperature = temperature, d.isWhiteBalanceModeSupported(.locked) {
                    var gains = d.deviceWhiteBalanceGains(for:AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature:temperature,tint:0))
                    gains.redGain = min(d.maxWhiteBalanceGain,max(1,gains.redGain)); gains.greenGain = min(d.maxWhiteBalanceGain,max(1,gains.greenGain)); gains.blueGain = min(d.maxWhiteBalanceGain,max(1,gains.blueGain))
                    d.setWhiteBalanceModeLocked(with:gains,completionHandler:nil)
                }
            } catch { self.fail(error) }
        }
    }

    func chooseCamera(front: Bool, ultraWide: Bool = false) {
        queue.async {
            guard self.recorder == nil && !self.state.finishing, let old = self.cameraInput else { return }
            var type = AVCaptureDevice.DeviceType.builtInWideAngleCamera
            if #available(iOS 13.0, *), ultraWide && !front { type = .builtInUltraWideCamera }
            guard let camera = AVCaptureDevice.default(type, for: .video, position: front ? .front : .back) else { return }
            do {
                let next = try AVCaptureDeviceInput(device: camera)
                if old.device.hasTorch { try old.device.lockForConfiguration(); old.device.torchMode = .off; old.device.unlockForConfiguration() }
                self.session.beginConfiguration(); self.session.removeInput(old)
                if self.session.canAddInput(next) { self.session.addInput(next); self.cameraInput = next }
                else { self.session.addInput(old) }
                self.session.commitConfiguration()
                self.session.beginConfiguration(); self.applyResolution(); self.session.commitConfiguration()
                try self.configureDevice(self.cameraInput!.device); self.configureConnection()
                self.zoom = 1; self.state.front = self.cameraInput!.device.position == .front; self.state.ultraSelected = ultraWide && !front; self.state.torch = false; self.publish()
            } catch { self.fail(error) }
        }
    }

    func toggleTorch() {
        queue.async {
            guard let device = self.cameraInput?.device, device.hasTorch, device.isTorchAvailable else { return }
            do {
                try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                if device.torchMode == .on { device.torchMode = .off } else { try device.setTorchModeOn(level: 0.3) }
                self.state.torch = device.torchMode == .on; self.publish()
            } catch { self.fail(error) }
        }
    }

    func setTorchBrightness(_ value: Float) {
        queue.async {
            guard let device = self.cameraInput?.device, device.hasTorch, device.isTorchAvailable else { return }
            do {
                try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                if value <= 0 { device.torchMode = .off }
                else { try device.setTorchModeOn(level: min(AVCaptureDevice.maxAvailableTorchLevel, max(0.01, value))) }
                self.state.torch = value > 0; self.publish()
            } catch { self.fail(error) }
        }
    }

    func toggleRecording() {
        queue.async {
            if self.recorder != nil { self.finishRecording(); return }
            guard self.state.ready && !self.state.finishing else { return }
            do {
                let root = try Self.library()
                let capacity = (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? 0
                guard capacity > 150_000_000 else { throw CameraFailure.message("Для записи нужно не менее 150 МБ свободного места") }
                let file = root.appendingPathComponent("Horizon-\(UUID().uuidString).mov")
                let audio = self.audioEnabled ? self.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) : nil
                self.recorder = try MovieRecorder(url: file, size: self.outputSize, audioSettings: audio, context: self.context)
                self.startedAt = nil; self.state.recording = true; self.state.duration = 0; self.publish()
            } catch { self.fail(error) }
        }
    }

    private func finishRecording() {
        guard let current = recorder else { return }
        recorder = nil; state.recording = false; state.finishing = true; state.message = "Сохранение видео…"; publish()
        current.finish { result in self.queue.async {
            self.state.finishing = false
            switch result {
            case .success(let url):
                self.state.message = "Видео сохранено в приложении"
                DispatchQueue.main.async { self.onSaved?(url) }
            case .failure(let error): self.state.message = error.localizedDescription
            }
            self.publish()
        } }
    }

    func stillFrame() {
        queue.async {
            guard let frame = self.latestImage else { self.state.message = "Ожидание первого кадра…"; self.publish(); return }
            do {
                guard let cg = self.context.createCGImage(frame, from: frame.extent), let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.94) else { return }
                let file = try Self.library().appendingPathComponent("Frame-\(UUID().uuidString).jpg")
                try data.write(to: file, options: .atomic)
                DispatchQueue.main.async { self.onSaved?(file) }; self.state.message = "Стоп-кадр сохранён"; self.publish()
            } catch { self.fail(error) }
        }
    }

    func stop() {
        queue.async {
            self.generation += 1; self.starting = false
            self.finishRecording(); self.motion.stop()
            if self.session.isRunning { self.session.stopRunning() }
            self.latestImage = nil
            self.state.ready = false; self.publish()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Camera delivery must never build an unbounded queue in front of a Stop tap.
        let isAudio = output === audioOutput
        let permit = isAudio ? audioPermit : videoPermit
        guard permit.wait(timeout: .now()) == .success else { return }
        queue.async {
            defer { permit.signal() }
            if isAudio { self.recorder?.append(audio: sample) }
            else { self.processVideo(sample) }
        }
    }

    private func processVideo(_ sample: CMSampleBuffer) {
        guard session.isRunning else { return }
        autoreleasepool {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            let input = CIImage(cvPixelBuffer: buffer)
            let roll = options.horizon ? motion.angle(at: CMTimeGetSeconds(time)) : 0
            if CMTimeGetSeconds(time) - lastMotionStatus > 0.3 {
                lastMotionStatus = CMTimeGetSeconds(time)
                let diagnostic = motion.diagnostic
                state.motionReady = diagnostic.ready; state.tilt = roll * 180 / .pi
                state.motionStatus = !options.horizon ? "Стабилизация выключена" :
                    diagnostic.error.map { "Датчики: \($0)" } ?? (diagnostic.ready ? "Стабилизация включена" : "Ожидание датчиков — держите iPhone вертикально")
                publish()
            }
            let output = outputSize
            let geometry = HorizonGeometry.make(source: input.extent.size, output: output, angle: roll, mode: options.horizon ? options.crop : .dynamic, previousZoom: options.horizon ? zoom : 1)
            zoom = geometry.zoom
            let corrected = input.transformed(by: CGAffineTransform(translationX: -input.extent.midX, y: -input.extent.midY))
                // The delivered portrait buffer is explicitly unmirrored for both cameras.
                // Core Image uses a bottom-left origin: gravity roll is the correcting rotation.
                .transformed(by: CGAffineTransform(rotationAngle: CGFloat(roll)))
                .cropped(to: geometry.crop)
                .transformed(by: CGAffineTransform(translationX: -geometry.crop.minX, y: -geometry.crop.minY))
                .transformed(by: CGAffineTransform(scaleX: output.width / geometry.crop.width, y: output.height / geometry.crop.height))
                .cropped(to: CGRect(origin: .zero, size: output))
            let zoomed: CIImage
            if digitalZoom > 1.001 {
                let crop = CameraZoom.crop(corrected.extent, factor: digitalZoom)
                zoomed = corrected.cropped(to: crop)
                    .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                    .transformed(by: CGAffineTransform(scaleX: CGFloat(digitalZoom), y: CGFloat(digitalZoom)))
                    .cropped(to: corrected.extent)
            } else { zoomed = corrected }
            latestImage = zoomed; onFrame?(zoomed); recorder?.append(image: zoomed, at: time)
            if !state.ready { state.ready = true; publish() }
            if let error = recorder?.failure { fail(error); finishRecording() }
            if recorder != nil {
                let seconds = CMTimeGetSeconds(time)
                if startedAt == nil { startedAt = seconds }
                if seconds - lastStateTime > 0.2 { state.duration = max(0, seconds - (startedAt ?? seconds)); lastStateTime = seconds; publish() }
            }
        }
    }

    static func library() throws -> URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil); return url
    }
    private func fail(_ error: Error) { state.message = error.localizedDescription; publish() }
    private func publish() { let value = state; DispatchQueue.main.async { self.onState?(value) } }
}

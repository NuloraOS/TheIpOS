import AVFoundation
import CoreImage
import Photos
import UIKit

enum CameraFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

final class CameraEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    struct Options { var horizon = true; var crop = CropMode.dynamic; var shape = FrameShape.portrait }
    struct State {
        var ready = false, recording = false, finishing = false, ultraWide = false, torch = false, front = false, ultraSelected = false, motionAvailable = true
        var message = "Подготовка камеры…"
        var duration = 0.0
        var motionReady = false, tilt = 0.0
        var motionStatus = "Ожидание датчиков…"
    }
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "camera.capture", qos: .userInitiated)
    var onFrame: ((CIImage) -> Void)?
    var onState: ((State) -> Void)?
    var onSaved: ((URL) -> Void)?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let motion = MotionTracker()
    private var options = Options(), state = State()
    private var cameraInput: AVCaptureDeviceInput?
    private var recorder: MovieRecorder?
    private var configured = false, audioEnabled = false
    private var zoom = 1.0, startedAt: Double?, lastStateTime = 0.0, lastMotionStatus = 0.0
    private var latestImage: CIImage?

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            guard let self = self else { return }
            guard allowed else { self.queue.async { self.state.message = "Разрешите доступ к камере в настройках iPhone"; self.publish() }; return }
            AVCaptureDevice.requestAccess(for: .audio) { microphone in
                self.queue.async {
                    do {
                        if !self.configured { try self.configure(microphone: microphone) }
                        if !self.session.isRunning { self.session.startRunning() }
                        if self.options.horizon { self.motion.start() }
                        self.state.ready = true; self.state.message = self.audioEnabled ? "720p · до 30 кадров/с" : "720p · запись без микрофона"
                        self.publish()
                    } catch { self.fail(error) }
                }
            }
        }
    }

    private func configure(microphone: Bool) throws {
        session.beginConfiguration(); defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CameraFailure.message("Камера недоступна") }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input), session.canAddOutput(videoOutput) else { throw CameraFailure.message("Камеру не удалось настроить") }
        session.addInput(input); cameraInput = input
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue); session.addOutput(videoOutput)
        if microphone, let mic = AVCaptureDevice.default(for: .audio), let audioInput = try? AVCaptureDeviceInput(device: mic), session.canAddInput(audioInput), session.canAddOutput(audioOutput) {
            session.addInput(audioInput); session.addOutput(audioOutput)
            audioOutput.setSampleBufferDelegate(self, queue: queue); audioEnabled = true
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
            self.options = newOptions; self.options.horizon = newOptions.horizon && self.motion.available
            self.zoom = 1; self.configureConnection()
            if self.options.horizon && self.session.isRunning { self.motion.start() } else { self.motion.stop() }
            if newOptions.horizon && !self.motion.available { self.state.message = "Датчики движения недоступны — обычный режим"; self.publish() }
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
            guard self.state.ready && !self.state.finishing else { return }
            if self.recorder != nil { self.finishRecording(); return }
            do {
                let root = try Self.library()
                let capacity = (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? 0
                guard capacity > 150_000_000 else { throw CameraFailure.message("Для записи нужно не менее 150 МБ свободного места") }
                let file = root.appendingPathComponent("Horizon-\(UUID().uuidString).mov")
                let audio = self.audioEnabled ? self.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) : nil
                self.recorder = try MovieRecorder(url: file, size: self.options.shape.size, audioSettings: audio, context: self.context)
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
            guard let frame = self.latestImage else { return }
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
            self.finishRecording(); self.motion.stop()
            if self.session.isRunning { self.session.stopRunning() }
            self.state.ready = false; self.publish()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === audioOutput { recorder?.append(audio: sample); return }
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
            let geometry = HorizonGeometry.make(source: input.extent.size, output: options.shape.size, angle: roll, mode: options.horizon ? options.crop : .dynamic, previousZoom: options.horizon ? zoom : 1)
            zoom = geometry.zoom
            let corrected = input.transformed(by: CGAffineTransform(translationX: -input.extent.midX, y: -input.extent.midY))
                // The delivered portrait buffer is explicitly unmirrored for both cameras.
                // Core Image uses a bottom-left origin: gravity roll is the correcting rotation.
                .transformed(by: CGAffineTransform(rotationAngle: CGFloat(roll)))
                .cropped(to: geometry.crop)
                .transformed(by: CGAffineTransform(translationX: -geometry.crop.minX, y: -geometry.crop.minY))
                .transformed(by: CGAffineTransform(scaleX: options.shape.size.width / geometry.crop.width, y: options.shape.size.height / geometry.crop.height))
                .cropped(to: CGRect(origin: .zero, size: options.shape.size))
            latestImage = corrected; onFrame?(corrected); recorder?.append(image: corrected, at: time)
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

import AVFoundation
import CoreImage

// All methods except finish's completion execute on CameraEngine's sample queue.
final class MovieRecorder {
    let url: URL
    let size: CGSize
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput?
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let context: CIContext
    private var firstTime: CMTime?
    private var lastVideoTime: CMTime?
    private(set) var failure: Error?

    init(url: URL, size: CGSize, audioSettings: [String: Any]?, context: CIContext) throws {
        self.url = url; self.size = size; self.context = context
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000,
                                               AVVideoExpectedSourceFrameRateKey: 30,
                                               AVVideoMaxKeyFrameIntervalKey: 30]
        ])
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw CameraFailure.message("Не удалось подготовить запись видео") }
        writer.add(video)
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        if let settings = audioSettings {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) { writer.add(input); audio = input } else { audio = nil }
        } else { audio = nil }
    }

    func append(image: CIImage, at time: CMTime) {
        guard failure == nil, time.isValid else { return }
        if firstTime == nil {
            guard writer.startWriting() else { failure = writer.error; return }
            writer.startSession(atSourceTime: time); firstTime = time
        }
        guard writer.status == .writing, video.isReadyForMoreMediaData,
              lastVideoTime == nil || CMTimeCompare(time, lastVideoTime!) > 0,
              let pool = adaptor.pixelBufferPool else { return }
        var pixel: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel)
        guard result == kCVReturnSuccess, let buffer = pixel else {
            failure = CameraFailure.message("Недостаточно памяти для записи"); return
        }
        context.render(image, to: buffer, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpaceCreateDeviceRGB())
        if adaptor.append(buffer, withPresentationTime: time) { lastVideoTime = time }
        else { failure = writer.error ?? CameraFailure.message("Кадр не записан") }
    }

    func append(audio sample: CMSampleBuffer) {
        guard let first = firstTime, writer.status == .writing, failure == nil,
              let audio = audio, audio.isReadyForMoreMediaData,
              CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample), first) >= 0 else { return }
        if !audio.append(sample) { failure = writer.error }
    }

    func finish(_ completion: @escaping (Result<URL, Error>) -> Void) {
        guard firstTime != nil else {
            writer.cancelWriting(); completion(.failure(CameraFailure.message("Нет кадров для сохранения"))); return
        }
        if let failure = failure { writer.cancelWriting(); completion(.failure(failure)); return }
        video.markAsFinished(); audio?.markAsFinished()
        writer.finishWriting { [self] in
            if writer.status == .completed { completion(.success(url)) }
            else { completion(.failure(writer.error ?? CameraFailure.message("Видео не сохранено"))) }
        }
    }
}

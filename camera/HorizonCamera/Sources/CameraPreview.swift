import UIKit
import MetalKit
import CoreImage

enum CameraGPU {
    static let device = MTLCreateSystemDefaultDevice()
    static let context: CIContext = {
        if let device = device { return CIContext(mtlDevice: device, options: [.cacheIntermediates: false]) }
        return CIContext(options: [.cacheIntermediates: false])
    }()
}

final class CameraPreview: MTKView, MTKViewDelegate {
    private let imageLock = NSLock()
    private var image: CIImage?
    private var requestPending = false
    private let inFlight = DispatchSemaphore(value: 2)
    private let commands = CameraGPU.device?.makeCommandQueue()
    private let gridLayer = CAShapeLayer()
    var grid = false { didSet { gridLayer.isHidden = !grid } }

    init() {
        super.init(frame: .zero, device: CameraGPU.device)
        backgroundColor = .black; clearColor = MTLClearColorMake(0, 0, 0, 1)
        framebufferOnly = false; autoResizeDrawable = false
        isPaused = true; enableSetNeedsDisplay = true
        delegate = self
        gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        gridLayer.fillColor = nil; gridLayer.lineWidth = 0.5; gridLayer.isHidden = true
        layer.addSublayer(gridLayer)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func display(_ frame: CIImage) {
        imageLock.lock(); image = frame
        let request = !requestPending; requestPending = true; imageLock.unlock()
        if request { DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.imageLock.lock(); self.requestPending = false; self.imageLock.unlock()
            if self.window != nil { self.setNeedsDisplay() }
        } }
    }
    func clear() { imageLock.lock(); image = nil; imageLock.unlock() }
    override func layoutSubviews() {
        super.layoutSubviews()
        // A7 does not need a native-resolution render target for the preview. Recording stays 720p.
        let scale = min(UIScreen.main.scale, 960 / max(1, max(bounds.width, bounds.height)))
        drawableSize = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        let path = UIBezierPath()
        for n in 1...2 {
            let x = bounds.width * CGFloat(n) / 3, y = bounds.height * CGFloat(n) / 3
            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: bounds.height))
            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        gridLayer.frame = bounds; gridLayer.path = path.cgPath
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
    func draw(in view: MTKView) {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        imageLock.lock(); let frame = image; imageLock.unlock()
        guard let current = frame, let commands = commands, let drawable = currentDrawable,
              let command = commands.makeCommandBuffer() else { inFlight.signal(); return }
        let size = drawableSize
        let scale = min(size.width / current.extent.width, size.height / current.extent.height)
        let fitted = current.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: (size.width - current.extent.width * scale) / 2, y: (size.height - current.extent.height * scale) / 2))
        let background = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        CameraGPU.context.render(fitted.composited(over: background), to: drawable.texture, commandBuffer: command, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpaceCreateDeviceRGB())
        let semaphore = inFlight
        command.addCompletedHandler { _ in semaphore.signal() }
        command.present(drawable); command.commit()
    }
}

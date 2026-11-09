import UIKit
import MetalKit
import CoreImage

final class CameraPreview: MTKView, MTKViewDelegate {
    private let imageLock = NSLock()
    private var image: CIImage?
    private var context: CIContext!
    private var commands: MTLCommandQueue!
    var grid = false { didSet { gridLayer.isHidden = !grid } }
    private let gridLayer = CAShapeLayer()

    init() {
        let gpu = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: gpu)
        backgroundColor = .black; clearColor = MTLClearColorMake(0, 0, 0, 1)
        framebufferOnly = false; preferredFramesPerSecond = 30
        if let gpu = gpu { context = CIContext(mtlDevice: gpu, options: [.cacheIntermediates: false]); commands = gpu.makeCommandQueue() }
        delegate = self
        gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.4).cgColor; gridLayer.fillColor = nil; gridLayer.lineWidth = 0.5; gridLayer.isHidden = true
        layer.addSublayer(gridLayer)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func display(_ frame: CIImage) { imageLock.lock(); image = frame; imageLock.unlock() }
    override func layoutSubviews() {
        super.layoutSubviews()
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
        imageLock.lock(); let current = image; imageLock.unlock()
        guard let frame = current, let context = context, let commands = commands,
              let drawable = currentDrawable, let command = commands.makeCommandBuffer() else { return }
        let size = drawableSize
        let scale = min(size.width / frame.extent.width, size.height / frame.extent.height)
        let fitted = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: (size.width - frame.extent.width * scale) / 2, y: (size.height - frame.extent.height * scale) / 2))
        let background = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        context.render(fitted.composited(over: background), to: drawable.texture, commandBuffer: command, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpaceCreateDeviceRGB())
        command.present(drawable); command.commit()
    }
}

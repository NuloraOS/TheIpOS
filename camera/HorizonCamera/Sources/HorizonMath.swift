import Foundation
import CoreGraphics

enum FrameShape: Int, CaseIterable {
    case portrait, classic, square
    var title: String { ["9:16", "4:3", "1:1"][rawValue] }
    var size: CGSize { [CGSize(width: 720, height: 1280), CGSize(width: 720, height: 960), CGSize(width: 720, height: 720)][rawValue] }
}

enum CropMode: Int { case dynamic, fixed }

enum CameraZoom {
    static func drag(_ initial: Double, delta: Double, width: Double) -> Double { clamp(initial * pow(120, delta / max(1,width))) }
    static func clamp(_ value: Double) -> Double { value.isFinite ? min(120, max(1, value)) : 1 }
    static func crop(_ bounds: CGRect, factor: Double) -> CGRect {
        let factor = CGFloat(clamp(factor))
        return CGRect(x: bounds.midX - bounds.width / factor / 2, y: bounds.midY - bounds.height / factor / 2, width: bounds.width / factor, height: bounds.height / factor)
    }
}

struct HorizonGeometry {
    let crop: CGRect
    let zoom: Double
    static func make(source: CGSize, output: CGSize, angle: Double, mode: CropMode, previousZoom: Double) -> HorizonGeometry {
        let w = Double(source.width), h = Double(source.height)
        let aspect = Double(output.width / output.height)
        let baseW = min(w, h * aspect), baseH = baseW / aspect
        let c = abs(cos(angle)), s = abs(sin(angle))
        let needed = max(1, (baseW * c + baseH * s) / w, (baseW * s + baseH * c) / h)
        let fixed = max(1, hypot(baseW, baseH) / min(w, h))
        // Zoom out gently, but zoom in immediately enough to avoid exposing corners.
        let safe = (mode == .fixed ? fixed : needed) * 1.015
        let zoom = mode == .fixed ? safe : max(safe, previousZoom + (safe - previousZoom) * 0.14)
        return HorizonGeometry(crop: CGRect(x: -baseW / zoom / 2, y: -baseH / zoom / 2,
                                           width: baseW / zoom, height: baseH / zoom), zoom: zoom)
    }
}

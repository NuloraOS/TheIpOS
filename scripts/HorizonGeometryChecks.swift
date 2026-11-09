import Foundation
import CoreGraphics

@main struct HorizonGeometryChecks {
    static func main() {
        precondition(CameraZoom.drag(2, delta:0, width:320)==2)
        precondition(CameraZoom.drag(2, delta:80, width:320)>2)
        precondition(CameraZoom.drag(2, delta:-80, width:320)<2)
        precondition(CameraZoom.drag(2, delta:10000, width:320)==120)
        precondition(CameraZoom.drag(2, delta:-10000, width:320)==1)
        var checks = 0
        for source in [CGSize(width: 720, height: 1280), CGSize(width: 1280, height: 720)] {
            for shape in FrameShape.allCases {
                for mode in [CropMode.dynamic, .fixed] {
                    var previous = 1.0
                    for degrees in stride(from: -360.0, through: 360.0, by: 3) {
                        let angle = degrees * .pi / 180
                        let geometry = HorizonGeometry.make(source: source, output: shape.size, angle: angle, mode: mode, previousZoom: previous)
                        previous = geometry.zoom
                        precondition(geometry.zoom.isFinite && geometry.zoom >= 1)
                        precondition(abs(geometry.crop.width / geometry.crop.height - shape.size.width / shape.size.height) < 0.00001)
                        for x in [geometry.crop.minX, geometry.crop.maxX] {
                            for y in [geometry.crop.minY, geometry.crop.maxY] {
                                let px = Double(x) * cos(angle) - Double(y) * sin(angle)
                                let py = Double(x) * sin(angle) + Double(y) * cos(angle)
                                precondition(abs(px) <= Double(source.width) / 2 + 0.001 && abs(py) <= Double(source.height) / 2 + 0.001, "Exposed corner")
                            }
                        }
                        checks += 1
                    }
                }
            }
        }
        print("PASS: \(checks) stabilization crop cases; physical sensor direction still requires an iPhone test")
    }
}

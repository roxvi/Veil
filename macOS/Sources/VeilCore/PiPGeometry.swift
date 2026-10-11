import Foundation
import CoreGraphics

public enum PiPGeometry {
    public static let padding: CGFloat = 6
    public static func valid(_ r: CGRect) -> Bool {
        [r.minX, r.minY, r.width, r.height].allSatisfy(\.isFinite) && r.width >= 1 && r.height >= 1
    }
    public static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        guard valid(a), valid(b) else { return 0 }
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height / min(a.width * a.height, b.width * b.height)
    }
    public static func fit(_ rect: CGRect, aspect: CGFloat, padding: CGFloat = 6) -> CGRect {
        guard valid(rect), aspect.isFinite, aspect > 0 else { return .zero }
        let inset = max(0, min(padding, (rect.width - 1) / 2, (rect.height - 1) / 2))
        let inside = rect.insetBy(dx: inset, dy: inset)
        let width = min(inside.width, inside.height * aspect)
        return CGRect(x: inside.midX - width / 2, y: inside.midY - width / aspect / 2,
                      width: width, height: width / aspect)
    }
    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

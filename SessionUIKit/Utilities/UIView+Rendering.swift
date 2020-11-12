import UIKit

public extension UIView {

    func toImage(isOpaque: Bool, scale: CGFloat) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = isOpaque
        let renderer = UIGraphicsImageRenderer(bounds: self.bounds, format: format)
        return renderer.image { context in
            self.layer.render(in: context.cgContext)
        }
    }
}

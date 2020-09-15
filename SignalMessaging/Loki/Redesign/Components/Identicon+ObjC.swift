
@objc(LKIdenticon)
public final class Identicon : NSObject {
    
    @objc public static func generatePlaceholderIcon(seed: String, text: String, size: CGFloat) -> UIImage {
        let icon = PlaceholderIcon(seed: seed)
        let layer = icon.generateLayer(with: size, text: text.substring(to: 1))
        let rect = CGRect(origin: CGPoint.zero, size: layer.frame.size)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        return renderer.image { layer.render(in: $0.cgContext) }
    }
}

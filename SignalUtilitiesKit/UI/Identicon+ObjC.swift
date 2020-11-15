
@objc(LKIdenticon)
public final class Identicon : NSObject {
    
    @objc public static func generatePlaceholderIcon(seed: String, text: String, size: CGFloat) -> UIImage {
        let icon = PlaceholderIcon(seed: seed)
        var content = text
        if content.count > 2 && content.hasPrefix("05") {
            content.removeFirst(2)
        }
        let layer = icon.generateLayer(with: size, text: content.substring(to: 1))
        let rect = CGRect(origin: CGPoint.zero, size: layer.frame.size)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        return renderer.image { layer.render(in: $0.cgContext) }
    }
}

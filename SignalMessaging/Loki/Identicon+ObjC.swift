@objc(LKIdenticon)
final class Identicon : NSObject {
    
    @objc static func generateIcon(string: String, size: CGFloat) -> UIImage {
        let icon = JazzIcon(seed: string)
        let iconLayer = icon.generateLayer(ofSize: size)
        let rect = CGRect(origin: CGPoint.zero, size: iconLayer.frame.size)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let image = renderer.image {
            context in
            
            return iconLayer.render(in: context.cgContext)
        }
        return image
    }
}

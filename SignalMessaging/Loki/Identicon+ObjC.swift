import IGIdenticon

@objc(LKIdenticon)
final class Identicon : NSObject {
    
//    @objc static func generateIcon(string: String, size: CGSize) -> UIImage {
//        let identicon = IGIdenticon.Identicon().icon(from: string, size: size)!
//        let rect = CGRect(origin: CGPoint.zero, size: identicon.size)
//        UIGraphicsBeginImageContextWithOptions(identicon.size, false, UIScreen.main.scale)
//        let context = UIGraphicsGetCurrentContext()!
//        context.setFillColor(UIColor.white.cgColor)
//        context.fill(rect)
//        context.draw(identicon.cgImage!, in: rect)
//        context.drawPath(using: CGPathDrawingMode.fill)
//        let result = UIGraphicsGetImageFromCurrentImageContext()!
//        UIGraphicsEndImageContext()
//        return result
//    }
    
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

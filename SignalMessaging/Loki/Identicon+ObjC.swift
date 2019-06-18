import IGIdenticon

@objc(LKIdenticon)
final class Identicon : NSObject {
    
    @objc static func generateIcon(string: String, size: CGSize) -> UIImage {
        let identicon = IGIdenticon.Identicon().icon(from: string, size: size)!
        let rect = CGRect(origin: CGPoint.zero, size: identicon.size)
        UIGraphicsBeginImageContextWithOptions(identicon.size, false, UIScreen.main.scale)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)
        context.draw(identicon.cgImage!, in: rect)
        context.drawPath(using: CGPathDrawingMode.fill)
        let result = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return result
    }
}

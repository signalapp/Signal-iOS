import IGIdenticon

@objc(LKIdenticon)
final class Identicon : NSObject {
    
    @objc static func generateIcon(string: String, size: CGSize) -> UIImage {
        return IGIdenticon.Identicon().icon(from: string, size: size)!
    }
}

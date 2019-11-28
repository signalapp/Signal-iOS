
@objc public extension UIColor {

    @objc convenience init(hex value: UInt) { // Doesn't need to be declared public because the extension is already public
        let red = CGFloat((value >> 16) & 0xff) / 255
        let green = CGFloat((value >> 8) & 0xff) / 255
        let blue = CGFloat((value >> 0) & 0xff) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

@objc(LKColors)
public final class Colors : NSObject {
    
    @objc public static let accent = UIColor(hex: 0x00F782)
    @objc public static let text = UIColor(hex: 0xFFFFFF)
    @objc public static let unimportant = UIColor(hex: 0xD8D8D8)
    @objc public static let border = UIColor(hex: 0x979797)
}

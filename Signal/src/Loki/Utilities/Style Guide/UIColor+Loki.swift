
@objc public extension UIColor {

    @objc public convenience init(hex value: UInt) {
        let red = CGFloat((value >> 16) & 0xff) / 255
        let green = CGFloat((value >> 8) & 0xff) / 255
        let blue = CGFloat((value >> 0) & 0xff) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
    
    @objc public static let accent = UIColor(hex: 0x00F782)
    @objc public static let text = UIColor(hex: 0xFFFFFF)
}

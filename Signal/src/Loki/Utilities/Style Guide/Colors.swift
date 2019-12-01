
@objc extension UIColor {

    @objc convenience init(hex value: UInt) {
        let red = CGFloat((value >> 16) & 0xff) / 255
        let green = CGFloat((value >> 8) & 0xff) / 255
        let blue = CGFloat((value >> 0) & 0xff) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

@objc(LKColors)
final class Colors : NSObject {
    
    @objc static let accent = UIColor(hex: 0x00F782)
    @objc static let text = UIColor(hex: 0xFFFFFF)
    @objc static let unimportant = UIColor(hex: 0xD8D8D8)
    @objc static let profilePictureBorder = UIColor(hex: 0x979797)
    @objc static let conversationCellBackground = UIColor(hex: 0x1B1B1B)
    @objc static let conversationCellSelected = UIColor(hex: 0x0C0C0C)
    @objc static let navigationBarBackground = UIColor(hex: 0x161616)
    @objc static let searchBarPlaceholder = UIColor(hex: 0x8E8E93) // Also used for the icons
    @objc static let searchBarBackground = UIColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 0.12)
    @objc static let newConversationButtonShadow = UIColor(hex: 0x077C44)
}

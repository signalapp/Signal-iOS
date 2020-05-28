
@objc public extension UIColor {

    @objc convenience init(hex value: UInt) {
        let red = CGFloat((value >> 16) & 0xff) / 255
        let green = CGFloat((value >> 8) & 0xff) / 255
        let blue = CGFloat((value >> 0) & 0xff) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

@objc(LKColors)
public final class Colors : NSObject {
    
    @objc public static var accent = isLightMode ? UIColor(hex: 0x00E97B) : UIColor(hex: 0x00F782)
    @objc public static var text = isLightMode ? UIColor(hex: 0x000000) : UIColor(hex: 0xFFFFFF)
    @objc public static var destructive = UIColor(hex: 0xFF453A)
    @objc public static var unimportant = UIColor(hex: 0xD8D8D8)
    @objc public static var border = UIColor(hex: 0x979797)
    @objc public static var cellBackground = isLightMode ? UIColor(hex: 0xFCFCFC) : UIColor(hex: 0x1B1B1B)
    @objc public static var cellSelected = isLightMode ? UIColor(hex: 0xDFDFDF) : UIColor(hex: 0x0C0C0C)
    @objc public static var navigationBarBackground = isLightMode ? UIColor(hex: 0xFCFCFC) : UIColor(hex: 0x161616)
    @objc public static var searchBarPlaceholder = UIColor(hex: 0x8E8E93) // Also used for the icons
    @objc public static var searchBarBackground = UIColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 0.12)
    @objc public static var newConversationButtonShadow = UIColor(hex: 0x077C44)
    @objc public static var separator = UIColor(hex: 0x36383C)
    @objc public static var unimportantButtonBackground = isLightMode ? UIColor.clear : UIColor(hex: 0x323232)
    @objc public static var buttonBackground = isLightMode ? UIColor(hex: 0xFCFCFC) : UIColor(hex: 0x1B1B1B)
    @objc public static var settingButtonSelected = isLightMode ? UIColor(hex: 0xDFDFDF) : UIColor(hex: 0x0C0C0C)
    @objc public static var modalBackground = isLightMode ? UIColor(hex: 0xFCFCFC) : UIColor(hex: 0x101011)
    @objc public static var modalBorder = UIColor(hex: 0x212121)
    @objc public static var fakeChatBubbleBackground = isLightMode ? UIColor(hex: 0xF5F5F5) : UIColor(hex: 0x3F4146)
    @objc public static var fakeChatBubbleText = UIColor(hex: 0x000000)
    @objc public static var composeViewBackground = isLightMode ? UIColor(hex: 0xFCFCFC) : UIColor(hex: 0x1B1B1B)
    @objc public static var composeViewTextFieldBackground = isLightMode ? UIColor(hex: 0xEDEDED) : UIColor(hex: 0x141414)
    @objc public static var receivedMessageBackground = isLightMode ? UIColor(hex: 0xF5F5F5) : UIColor(hex: 0x222325)
    @objc public static var sentMessageBackground = isLightMode ? UIColor(hex: 0x00E97B) : UIColor(hex: 0x3F4146)
    @objc public static var newConversationButtonCollapsedBackground = isLightMode ? UIColor(hex: 0xF5F5F5) : UIColor(hex: 0x1F1F1F)
    @objc public static var pnOptionBackground = isLightMode ? UIColor(hex: 0xFCFCFC) : UIColor(hex: 0x1B1B1B)
    @objc public static var pnOptionBorder = UIColor(hex: 0x212121)
    @objc public static var pathsBuilding = UIColor(hex: 0xFFCE3A)
}

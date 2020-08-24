
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
    
    @objc public static var accent = UIColor(named: "session_accent")!
    @objc public static var text = UIColor(named: "session_text")!
    @objc public static var destructive = UIColor(named: "session_destructive")!
    @objc public static var unimportant = UIColor(named: "session_unimportant")!
    @objc public static var border = UIColor(named: "session_border")!
    @objc public static var cellBackground = UIColor(named: "session_cell_background")!
    @objc public static var cellSelected = UIColor(named: "session_cell_selected")!
    @objc public static var navigationBarBackground = UIColor(named: "session_navigation_bar_background")!
    @objc public static var searchBarPlaceholder = UIColor(named: "session_search_bar_placeholder")! // Also used for the icons
    @objc public static var searchBarBackground = UIColor(named: "session_search_bar_background")!
    @objc public static var newConversationButtonShadow = UIColor(named: "session_new_conversation_button_shadow")!
    @objc public static var separator = UIColor(named: "session_separator")!
    @objc public static var unimportantButtonBackground = UIColor(named: "session_unimportant_button_background")!
    @objc public static var buttonBackground = UIColor(named: "session_button_background")!
    @objc public static var settingButtonSelected = UIColor(named: "session_setting_button_selected")!
    @objc public static var modalBackground = UIColor(named: "session_modal_background")!
    @objc public static var modalBorder = UIColor(named: "session_modal_border")!
    @objc public static var fakeChatBubbleBackground = UIColor(named: "session_fake_chat_bubble_background")!
    @objc public static var fakeChatBubbleText = UIColor(named: "session_fake_chat_bubble_text")!
    @objc public static var composeViewBackground = UIColor(named: "session_compose_view_background")!
    @objc public static var composeViewTextFieldBackground = UIColor(named: "session_compose_view_text_field_background")!
    @objc public static var receivedMessageBackground = UIColor(named: "session_received_message_background")!
    @objc public static var sentMessageBackground = UIColor(named: "session_sent_message_background")!
    @objc public static var newConversationButtonCollapsedBackground = UIColor(named: "session_new_conversation_button_collapsed_background")!
    @objc public static var pnOptionBackground = UIColor(named: "session_pn_option_background")!
    @objc public static var pnOptionBorder = UIColor(named: "session_pn_option_border")!
    @objc public static var pathsBuilding = UIColor(named: "session_paths_building")!
}

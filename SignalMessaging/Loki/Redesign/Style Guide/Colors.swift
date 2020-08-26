
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
    
    @objc public static let accent = UIColor(named: "session_accent")!
    @objc public static let text = UIColor(named: "session_text")!
    @objc public static let destructive = UIColor(named: "session_destructive")!
    @objc public static let unimportant = UIColor(named: "session_unimportant")!
    @objc public static let border = UIColor(named: "session_border")!
    @objc public static let cellBackground = UIColor(named: "session_cell_background")!
    @objc public static let cellSelected = UIColor(named: "session_cell_selected")!
    @objc public static let navigationBarBackground = UIColor(named: "session_navigation_bar_background")!
    @objc public static let searchBarPlaceholder = UIColor(named: "session_search_bar_placeholder")! // Also used for the icons
    @objc public static let searchBarBackground = UIColor(named: "session_search_bar_background")!
    @objc public static let newConversationButtonShadow = UIColor(named: "session_new_conversation_button_shadow")!
    @objc public static let separator = UIColor(named: "session_separator")!
    @objc public static let unimportantButtonBackground = UIColor(named: "session_unimportant_button_background")!
    @objc public static let buttonBackground = UIColor(named: "session_button_background")!
    @objc public static let settingButtonSelected = UIColor(named: "session_setting_button_selected")!
    @objc public static let modalBackground = UIColor(named: "session_modal_background")!
    @objc public static let modalBorder = UIColor(named: "session_modal_border")!
    @objc public static let fakeChatBubbleBackground = UIColor(named: "session_fake_chat_bubble_background")!
    @objc public static let fakeChatBubbleText = UIColor(named: "session_fake_chat_bubble_text")!
    @objc public static let composeViewBackground = UIColor(named: "session_compose_view_background")!
    @objc public static let composeViewTextFieldBackground = UIColor(named: "session_compose_view_text_field_background")!
    @objc public static let receivedMessageBackground = UIColor(named: "session_received_message_background")!
    @objc public static let sentMessageBackground = UIColor(named: "session_sent_message_background")!
    @objc public static let newConversationButtonCollapsedBackground = UIColor(named: "session_new_conversation_button_collapsed_background")!
    @objc public static let pnOptionBackground = UIColor(named: "session_pn_option_background")!
    @objc public static let pnOptionBorder = UIColor(named: "session_pn_option_border")!
    @objc public static let pathsBuilding = UIColor(named: "session_paths_building")!
}

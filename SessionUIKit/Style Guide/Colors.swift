import UIKit

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
    
    @objc public static var grey: UIColor { UIColor(named: "session_grey")! }
    @objc public static var accent: UIColor { UIColor(named: "session_accent")! }
    @objc public static var text: UIColor { UIColor(named: "session_text")! }
    @objc public static var destructive: UIColor { UIColor(named: "session_destructive")! }
    @objc public static var unimportant: UIColor { UIColor(named: "session_unimportant")! }
    @objc public static var border: UIColor { UIColor(named: "session_border")! }
    @objc public static var cellBackground: UIColor { UIColor(named: "session_cell_background")! }
    @objc public static var cellSelected: UIColor { UIColor(named: "session_cell_selected")! }
    @objc public static var cellPinned: UIColor { UIColor(named: "session_cell_pinned")! }
    @objc public static var navigationBarBackground: UIColor { UIColor(named: "session_navigation_bar_background")! }
    @objc public static var searchBarPlaceholder: UIColor { UIColor(named: "session_search_bar_placeholder")! } // Also used for the icons
    @objc public static var searchBarBackground: UIColor { UIColor(named: "session_search_bar_background")! }
    @objc public static var expandedButtonGlowColor: UIColor { UIColor(named: "session_expanded_button_glow_color")! }
    @objc public static var separator: UIColor { UIColor(named: "session_separator")! }
    @objc public static var unimportantButtonBackground: UIColor { UIColor(named: "session_unimportant_button_background")! }
    @objc public static var buttonBackground: UIColor { UIColor(named: "session_button_background")! }
    @objc public static var settingButtonSelected: UIColor { UIColor(named: "session_setting_button_selected")! }
    @objc public static var modalBackground: UIColor { UIColor(named: "session_modal_background")! }
    @objc public static var modalBorder: UIColor { UIColor(named: "session_modal_border")! }
    @objc public static var fakeChatBubbleBackground: UIColor { UIColor(named: "session_fake_chat_bubble_background")! }
    @objc public static var fakeChatBubbleText: UIColor { UIColor(named: "session_fake_chat_bubble_text")! }
    @objc public static var composeViewBackground: UIColor { UIColor(named: "session_compose_view_background")! }
    @objc public static var composeViewTextFieldBackground: UIColor { UIColor(named: "session_compose_view_text_field_background")! }
    @objc public static var receivedMessageBackground: UIColor { UIColor(named: "session_received_message_background")! }
    @objc public static var sentMessageBackground: UIColor { UIColor(named: "session_sent_message_background")! }
    @objc public static var newConversationButtonCollapsedBackground: UIColor { UIColor(named: "session_new_conversation_button_collapsed_background")! }
    @objc public static var pnOptionBackground: UIColor { UIColor(named: "session_pn_option_background")! }
    @objc public static var pnOptionBorder: UIColor { UIColor(named: "session_pn_option_border")! }
    @objc public static var pathsBuilding: UIColor { UIColor(named: "session_paths_building")! }
    @objc public static var callMessageBackground: UIColor { UIColor(named: "session_call_message_background")! }
    @objc public static var pinIcon: UIColor { UIColor(named: "session_pin_icon")! }
    @objc public static var sessionHeading: UIColor { UIColor(named: "session_heading")! }
    @objc public static var sessionMessageRequestsBubble: UIColor { UIColor(named: "session_message_requests_bubble")! }
    @objc public static var sessionMessageRequestsIcon: UIColor { UIColor(named: "session_message_requests_icon")! }
    @objc public static var sessionMessageRequestsTitle: UIColor { UIColor(named: "session_message_requests_title")! }
    @objc public static var sessionMessageRequestsInfoText: UIColor { UIColor(named: "session_message_requests_info_text")! }
    @objc public static var sessionEmojiPlusButtonBackground: UIColor { UIColor(named: "session_emoji_plus_button_background")! }
    @objc public static var sessionContactsSearchBarBackground: UIColor { UIColor(named: "session_contacts_search_bar_background")! }
}

// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIColor
import SessionUtilitiesKit

// MARK: - Theme

public enum Theme: String, CaseIterable, Codable, EnumStringSetting {
    case classicDark = "classic_dark"
    case classicLight = "classic_light"
    case oceanDark = "ocean_dark"
    case oceanLight = "ocean_light"
    
    // MARK: - Properties
    
    public var title: String {
        switch self {
            case .classicDark: return "Classic Dark"
            case .classicLight: return "Classic Light"
            case .oceanDark: return "Ocean Dark"
            case .oceanLight: return "Ocean Light"
        }
    }
    
    public var colors: [ThemeValue: UIColor] {
        switch self {
            case .classicDark: return Theme_ClassicDark.theme
            case .classicLight: return Theme_ClassicLight.theme
            case .oceanDark: return Theme_OceanDark.theme
            case .oceanLight: return Theme_OceanLight.theme
        }
    }
    
    public var interfaceStyle: UIUserInterfaceStyle {
        switch self {
            case .classicDark, .oceanDark: return .dark
            case .classicLight, .oceanLight: return .light
        }
    }
    
    public var statusBarStyle: UIStatusBarStyle {
        switch self {
            case .classicDark, .oceanDark: return .lightContent
            case .classicLight, .oceanLight: return .darkContent
        }
    }
}

// MARK: - ThemeColors

public protocol ThemeColors {
    static var theme: [ThemeValue: UIColor] { get }
}

// MARK: - ThemeValue

public enum ThemeValue {
    // General
    case white
    case black
    case clear
    case primary
    case defaultPrimary
    case danger
    case disabled
    case backgroundPrimary
    case backgroundSecondary
    case textPrimary
    case textSecondary
    case borderSeparator
    
    // Path
    case path_connected
    case path_connecting
    case path_error
    case path_unknown
    
    // TextBox
    case textBox_background
    case textBox_border
    
    // MessageBubble
    case messageBubble_outgoingBackground
    case messageBubble_incomingBackground
    case messageBubble_outgoingText
    case messageBubble_incomingText
    case messageBubble_overlay
    
    // MenuButton
    case menuButton_background
    case menuButton_icon
    case menuButton_outerShadow
    case menuButton_innerShadow
    
    // RadioButton
    case radioButton_selectedBackground
    case radioButton_unselectedBackground
    case radioButton_selectedBorder
    case radioButton_unselectedBorder
    
    // OutlineButton
    case outlineButton_text
    case outlineButton_background
    case outlineButton_highlight
    case outlineButton_border
    case outlineButton_filledText
    case outlineButton_filledBackground
    case outlineButton_filledHighlight
    case outlineButton_destructiveText
    case outlineButton_destructiveBackground
    case outlineButton_destructiveHighlight
    case outlineButton_destructiveBorder
    
    // SolidButton
    case solidButton_background
    case solidButton_highlight
    
    // Settings
    case settings_tabBackground
    case settings_tabHighlight
    
    // Appearance
    case appearance_sectionBackground
    case appearance_buttonBackground
    case appearance_buttonHighlight
    
    // Alert
    case alert_background
    case alert_buttonBackground
    case alert_buttonHighlight
    
    // ConversationButton
    case conversationButton_background
    case conversationButton_highlight
    case conversationButton_unreadBackground
    case conversationButton_unreadHighlight
    case conversationButton_unreadStripBackground
    case conversationButton_unreadBubbleBackground
    case conversationButton_unreadBubbleText
    case conversationButton_swipeDestructive
    case conversationButton_swipeSecondary
    case conversationButton_swipeTertiary
    
    // InputButton
    case inputButton_background
    
    // ContextMenu
    case contextMenu_background
    case contextMenu_highlight
    case contextMenu_textHighlight
    
    // Call
    case callAccept_background
    case callDecline_background
    
    // Reactions
    case reactions_contextBackground
    case reactions_contextMoreBackground
}

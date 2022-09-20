// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIColor

internal enum Theme_ClassicDark: ThemeColors {
    static let theme: [ThemeValue: UIColor] = [
        // General
        .white: .white,
        .black: .black,
        .clear: .clear,
        .primary: .primary,
        .defaultPrimary: Theme.PrimaryColor.green.color,
        .danger: .dangerDark,
        .disabled: .disabledDark,
        .backgroundPrimary: .classicDark0,
        .backgroundSecondary: .classicDark1,
        .textPrimary: .classicDark6,
        .textSecondary: .classicDark5,
        .borderSeparator: .classicDark3,
        
        // Path
        .path_connected: .pathConnected,
        .path_connecting: .pathConnecting,
        .path_error: .pathError,
        .path_unknown: .classicDark4,
    
        // TextBox
        .textBox_background: .classicDark1,
        .textBox_border: .classicDark3,
    
        // MessageBubble
        .messageBubble_outgoingBackground: .primary,
        .messageBubble_incomingBackground: .classicDark2,
        .messageBubble_outgoingText: .classicDark0,
        .messageBubble_incomingText: .classicDark6,
        .messageBubble_overlay: .black_06,

        // MenuButton
        .menuButton_background: .primary,
        .menuButton_icon: .classicDark6,
        .menuButton_outerShadow: .primary,
        .menuButton_innerShadow: .classicDark6,
        
        // RadioButton
        .radioButton_selectedBackground: .primary,
        .radioButton_unselectedBackground: .clear,
        .radioButton_selectedBorder: .classicDark6,
        .radioButton_unselectedBorder: .classicDark6,
        
        // OutlineButton
        .outlineButton_text: .primary,
        .outlineButton_background: .clear,
        .outlineButton_highlight: .classicDark6.withAlphaComponent(0.3),
        .outlineButton_border: .primary,
        .outlineButton_filledText: .classicDark6,
        .outlineButton_filledBackground: .classicDark1,
        .outlineButton_filledHighlight: .classicDark3,
        .outlineButton_destructiveText: .dangerDark,
        .outlineButton_destructiveBackground: .clear,
        .outlineButton_destructiveHighlight: .dangerDark.withAlphaComponent(0.3),
        .outlineButton_destructiveBorder: .dangerDark,
        
        // SolidButton
        .solidButton_background: .classicDark3,
        .solidButton_highlight: .classicDark4,
        
        // Settings
        .settings_tabBackground: .classicDark1,
        .settings_tabHighlight: .classicDark3,
        
        // Appearance
        .appearance_sectionBackground: .classicDark1,
        .appearance_buttonBackground: .classicDark1,
        .appearance_buttonHighlight: .classicDark3,
        
        // Alert
        .alert_text: .classicDark6,
        .alert_background: .classicDark1,
        .alert_buttonBackground: .classicDark1,
        .alert_buttonHighlight: .classicDark3,
        
        // ConversationButton
        .conversationButton_background: .classicDark1,
        .conversationButton_highlight: .classicDark3,
        .conversationButton_unreadBackground: .classicDark2,
        .conversationButton_unreadHighlight: .classicDark3,
        .conversationButton_unreadStripBackground: .primary,
        .conversationButton_unreadBubbleBackground: .classicDark3,
        .conversationButton_unreadBubbleText: .classicDark6,
        .conversationButton_swipeDestructive: .dangerDark,
        .conversationButton_swipeSecondary: .classicDark2,
        .conversationButton_swipeTertiary: Theme.PrimaryColor.orange.color,
        
        // InputButton
        .inputButton_background: .classicDark1,
        
        // ContextMenu
        .contextMenu_background: .classicDark1,
        .contextMenu_highlight: .primary,
        .contextMenu_text: .classicDark6,
        .contextMenu_textHighlight: .classicDark0,
        
        // Call
        .callAccept_background: Theme.PrimaryColor.green.color,
        .callDecline_background: .dangerDark,
        
        // Reactions
        .reactions_contextBackground: .classicDark2,
        .reactions_contextMoreBackground: .classicDark1
    ]
}

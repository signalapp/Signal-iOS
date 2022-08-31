// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIColor

internal enum Theme_OceanDark: ThemeColors {
    static let theme: [ThemeValue: UIColor] = [
        // General
        .white: .white,
        .black: .black,
        .clear: .clear,
        .primary: .primary,
        .defaultPrimary: Theme.PrimaryColor.blue.color,
        .danger: .dangerDark,
        .disabled: .disabledDark,
        .backgroundPrimary: .oceanDark2,
        .backgroundSecondary: .oceanDark1,
        .textPrimary: .oceanDark6,
        .textSecondary: .oceanDark5,
        .borderSeparator: .oceanDark4,
        
        // Path
        .path_connected: .pathConnected,
        .path_connecting: .pathConnecting,
        .path_error: .pathError,
        .path_unknown: .oceanDark4,
    
        // TextBox
        .textBox_background: .oceanDark1,
        .textBox_border: .oceanDark4,
    
        // MessageBubble
        .messageBubble_outgoingBackground: .primary,
        .messageBubble_incomingBackground: .oceanDark4,
        .messageBubble_outgoingText: .oceanDark0,
        .messageBubble_incomingText: .oceanDark6,
        .messageBubble_overlay: .black_06,

        // MenuButton
        .menuButton_background: .primary,
        .menuButton_icon: .oceanDark6,
        .menuButton_outerShadow: .primary,
        .menuButton_innerShadow: .oceanDark6,
        
        // RadioButton
        .radioButton_selectedBackground: .primary,
        .radioButton_unselectedBackground: .clear,
        .radioButton_selectedBorder: .oceanDark6,
        .radioButton_unselectedBorder: .oceanDark6,
        
        // OutlineButton
        .outlineButton_text: .primary,
        .outlineButton_background: .clear,
        .outlineButton_highlight: .oceanDark6.withAlphaComponent(0.3),
        .outlineButton_border: .primary,
        .outlineButton_filledText: .oceanDark6,
        .outlineButton_filledBackground: .oceanDark1,
        .outlineButton_filledHighlight: .oceanDark3,
        .outlineButton_destructiveText: .dangerDark,
        .outlineButton_destructiveBackground: .clear,
        .outlineButton_destructiveHighlight: .dangerDark.withAlphaComponent(0.3),
        .outlineButton_destructiveBorder: .dangerDark,
        
        // SolidButton
        .solidButton_background: .oceanDark2,
        .solidButton_highlight: .oceanDark4,
        
        // Settings
        .settings_tabBackground: .oceanDark1,
        .settings_tabHighlight: .oceanDark3,
        
        // Appearance
        .appearance_sectionBackground: .oceanDark3,
        .appearance_buttonBackground: .oceanDark3,
        .appearance_buttonHighlight: .oceanDark4,
        
        // Alert
        .alert_background: .oceanDark3,
        .alert_buttonBackground: .oceanDark3,
        .alert_buttonHighlight: .oceanDark4,
        
        // ConversationButton
        .conversationButton_background: .oceanDark3,
        .conversationButton_highlight: .oceanDark3,
        .conversationButton_unreadBackground: .oceanDark2,
        .conversationButton_unreadHighlight: .oceanDark3,
        .conversationButton_unreadStripBackground: .primary,
        .conversationButton_unreadBubbleBackground: .primary,
        .conversationButton_unreadBubbleText: .oceanDark0,
        .conversationButton_swipeDestructive: .dangerDark,
        .conversationButton_swipeSecondary: .oceanDark2,
        .conversationButton_swipeTertiary: Theme.PrimaryColor.orange.color
    ]
}

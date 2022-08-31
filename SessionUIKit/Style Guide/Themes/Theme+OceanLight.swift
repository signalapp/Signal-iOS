// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIColor

internal enum Theme_OceanLight: ThemeColors {
    static let theme: [ThemeValue: UIColor] = [
        // General
        .white: .white,
        .black: .black,
        .clear: .clear,
        .primary: .primary,
        .defaultPrimary: Theme.PrimaryColor.blue.color,
        .danger: .dangerLight,
        .disabled: .disabledLight,
        .backgroundPrimary: .oceanLight6,
        .backgroundSecondary: .oceanLight5,
        .textPrimary: .oceanLight0,
        .textSecondary: .oceanLight1,
        .borderSeparator: .oceanLight2,
        
        // Path
        .path_connected: .pathConnected,
        .path_connecting: .pathConnecting,
        .path_error: .pathError,
        .path_unknown: .oceanLight4,
    
        // TextBox
        .textBox_background: .oceanLight6,
        .textBox_border: .oceanLight2,
    
        // MessageBubble
        .messageBubble_outgoingBackground: .primary,
        .messageBubble_incomingBackground: .oceanLight3,
        .messageBubble_outgoingText: .oceanLight0,
        .messageBubble_incomingText: .oceanLight0,
        .messageBubble_overlay: .black_06,

        // MenuButton
        .menuButton_background: .primary,
        .menuButton_icon: .white,
        .menuButton_outerShadow: .black,
        .menuButton_innerShadow: .white,
        
        // RadioButton
        .radioButton_selectedBackground: .primary,
        .radioButton_unselectedBackground: .clear,
        .radioButton_selectedBorder: .oceanLight0,
        .radioButton_unselectedBorder: .oceanLight2,
        
        // OutlineButton
        .outlineButton_text: .oceanLight0,
        .outlineButton_background: .clear,
        .outlineButton_highlight: .oceanLight0.withAlphaComponent(0.1),
        .outlineButton_border: .oceanLight0,
        .outlineButton_filledText: .oceanLight6,
        .outlineButton_filledBackground: .oceanLight0,
        .outlineButton_filledHighlight: .oceanLight1,
        .outlineButton_destructiveText: .dangerLight,
        .outlineButton_destructiveBackground: .clear,
        .outlineButton_destructiveHighlight: .dangerLight.withAlphaComponent(0.3),
        .outlineButton_destructiveBorder: .dangerLight,
        
        // SolidButton
        .solidButton_background: .oceanLight4,
        .solidButton_highlight: .oceanLight5,
        
        // Settings
        .settings_tabBackground: .oceanLight6,
        .settings_tabHighlight: .oceanLight4,
        
        // Appearance
        .appearance_sectionBackground: .oceanLight6,
        .appearance_buttonBackground: .oceanLight6,
        .appearance_buttonHighlight: .oceanLight4,
        
        // Alert
        .alert_background: .oceanLight6,
        .alert_buttonBackground: .oceanLight6,
        .alert_buttonHighlight: .oceanLight4,
        
        // ConversationButton
        .conversationButton_background: .oceanLight6,
        .conversationButton_highlight: .oceanLight4,
        .conversationButton_unreadBackground: .oceanLight5,
        .conversationButton_unreadHighlight: .oceanLight4,
        .conversationButton_unreadStripBackground: .primary,
        .conversationButton_unreadBubbleBackground: .primary,
        .conversationButton_unreadBubbleText: .oceanLight0,
        .conversationButton_swipeDestructive: .dangerLight,
        .conversationButton_swipeSecondary: .oceanLight1,
        .conversationButton_swipeTertiary: Theme.PrimaryColor.orange.color
    ]
}

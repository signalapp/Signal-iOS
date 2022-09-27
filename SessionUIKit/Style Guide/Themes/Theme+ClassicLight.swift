// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIColor

internal enum Theme_ClassicLight: ThemeColors {
    static let theme: [ThemeValue: UIColor] = [
        // General
        .white: .white,
        .black: .black,
        .clear: .clear,
        .primary: .primary,
        .defaultPrimary: Theme.PrimaryColor.green.color,
        .danger: .dangerLight,
        .disabled: .disabledLight,
        .backgroundPrimary: .classicLight6,
        .backgroundSecondary: .classicLight5,
        .textPrimary: .classicLight0,
        .textSecondary: .classicLight1,
        .borderSeparator: .classicLight2,
        
        // Path
        .path_connected: .pathConnected,
        .path_connecting: .pathConnecting,
        .path_error: .pathError,
        .path_unknown: .classicLight4,
    
        // TextBox
        .textBox_background: .classicLight6,
        .textBox_border: .classicLight2,
    
        // MessageBubble
        .messageBubble_outgoingBackground: .primary,
        .messageBubble_incomingBackground: .classicLight4,
        .messageBubble_outgoingText: .classicLight0,
        .messageBubble_incomingText: .classicLight0,
        .messageBubble_overlay: .black_06,

        // MenuButton
        .menuButton_background: .primary,
        .menuButton_icon: .classicLight6,
        .menuButton_outerShadow: .classicLight0,
        .menuButton_innerShadow: .classicLight6,
        
        // RadioButton
        .radioButton_selectedBackground: .primary,
        .radioButton_unselectedBackground: .clear,
        .radioButton_selectedBorder: .classicLight0,
        .radioButton_unselectedBorder: .classicLight0,
        
        // OutlineButton
        .outlineButton_text: .classicLight0,
        .outlineButton_background: .clear,
        .outlineButton_highlight: .classicLight0.withAlphaComponent(0.1),
        .outlineButton_border: .classicLight0,
        .outlineButton_filledText: .classicLight6,
        .outlineButton_filledBackground: .classicLight0,
        .outlineButton_filledHighlight: .classicLight1,
        .outlineButton_destructiveText: .dangerLight,
        .outlineButton_destructiveBackground: .clear,
        .outlineButton_destructiveHighlight: .dangerLight.withAlphaComponent(0.3),
        .outlineButton_destructiveBorder: .dangerLight,
        
        // SolidButton
        .solidButton_background: .classicLight3,
        .solidButton_highlight: .classicLight4,
        
        // Settings
        .settings_tabBackground: .classicLight5,
        .settings_tabHighlight: .classicLight3,
        
        // AppearanceButton
        .appearance_sectionBackground: .classicLight6,
        .appearance_buttonBackground: .classicLight6,
        .appearance_buttonHighlight: .classicLight4,
        
        // Alert
        .alert_text: .classicLight0,
        .alert_background: .classicLight6,
        .alert_buttonBackground: .classicLight6,
        .alert_buttonHighlight: .classicLight4,
        
        // ConversationButton
        .conversationButton_background: .classicLight6,
        .conversationButton_highlight: .classicLight4,
        .conversationButton_unreadBackground: .classicLight6,
        .conversationButton_unreadHighlight: .classicLight4,
        .conversationButton_unreadStripBackground: .primary,
        .conversationButton_unreadBubbleBackground: .classicLight3,
        .conversationButton_unreadBubbleText: .classicLight0,
        .conversationButton_swipeDestructive: .dangerLight,
        .conversationButton_swipeSecondary: .classicLight1,
        .conversationButton_swipeTertiary: Theme.PrimaryColor.orange.color,
        
        // InputButton
        .inputButton_background: .classicDark6,
        
        // ContextMenu
        .contextMenu_background: .classicLight6,
        .contextMenu_highlight: .primary,
        .contextMenu_text: .classicLight0,
        .contextMenu_textHighlight: .classicLight0,
        
        // Call
        .callAccept_background: Theme.PrimaryColor.green.color,
        .callDecline_background: .dangerLight,
        
        // Reactions
        .reactions_contextBackground: .classicLight4,
        .reactions_contextMoreBackground: .classicLight6
    ]
}

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
        .textPrimary: .oceanDark7,
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
        .messageBubble_incomingText: .oceanDark7,
        .messageBubble_overlay: .black_06,

        // MenuButton
        .menuButton_background: .primary,
        .menuButton_icon: .oceanDark7,
        .menuButton_outerShadow: .primary,
        .menuButton_innerShadow: .oceanDark7,
        
        // RadioButton
        .radioButton_selectedBackground: .primary,
        .radioButton_unselectedBackground: .clear,
        .radioButton_selectedBorder: .oceanDark7,
        .radioButton_unselectedBorder: .oceanDark7,
        
        // SessionButton
        .sessionButton_text: .primary,
        .sessionButton_background: .clear,
        .sessionButton_highlight: .oceanDark7.withAlphaComponent(0.3),
        .sessionButton_border: .primary,
        .sessionButton_filledText: .oceanDark7,
        .sessionButton_filledBackground: .oceanDark1,
        .sessionButton_filledHighlight: .oceanDark3,
        .sessionButton_destructiveText: .dangerDark,
        .sessionButton_destructiveBackground: .clear,
        .sessionButton_destructiveHighlight: .dangerDark.withAlphaComponent(0.3),
        .sessionButton_destructiveBorder: .dangerDark,
        
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
        .alert_text: .oceanDark7,
        .alert_background: .oceanDark3,
        .alert_buttonBackground: .oceanDark3,
        .alert_buttonHighlight: .oceanDark4,
        
        // ConversationButton
        .conversationButton_background: .oceanDark3,
        .conversationButton_highlight: .oceanDark4,
        .conversationButton_unreadBackground: .oceanDark2,
        .conversationButton_unreadHighlight: .oceanDark4,
        .conversationButton_unreadStripBackground: .primary,
        .conversationButton_unreadBubbleBackground: .primary,
        .conversationButton_unreadBubbleText: .oceanDark0,
        .conversationButton_swipeDestructive: .dangerDark,
        .conversationButton_swipeSecondary: .oceanDark2,
        .conversationButton_swipeTertiary: Theme.PrimaryColor.orange.color,
        
        // InputButton
        .inputButton_background: .oceanDark4,
        
        // ContextMenu
        .contextMenu_background: .oceanDark2,
        .contextMenu_highlight: .primary,
        .contextMenu_text: .oceanDark7,
        .contextMenu_textHighlight: .oceanDark0,
        
        // Call
        .callAccept_background: Theme.PrimaryColor.green.color,
        .callDecline_background: .dangerDark,
        
        // Reactions
        .reactions_contextBackground: .oceanDark1,
        .reactions_contextMoreBackground: .oceanDark2,
        
        // NewConversation
        .newConversation_background: .oceanDark3
    ]
}

// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIColor

internal enum Theme_ClassicDark: ThemeColors {
    static let theme: [ThemeValue: UIColor] = [
        // General
        .primary: .primary,
        .defaultPrimary: Theme.PrimaryColor.green.color,
        .danger: #colorLiteral(red: 1, green: 0.2274509804, blue: 0.2274509804, alpha: 1),
        .clear: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0),
        .backgroundPrimary: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1),
        .backgroundSecondary: #colorLiteral(red: 0.1058823529, green: 0.1058823529, blue: 0.1058823529, alpha: 1),
        .textPrimary: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1),
        .textSecondary: #colorLiteral(red: 0.631372549, green: 0.6352941176, blue: 0.631372549, alpha: 1),
        .borderSeparator: #colorLiteral(red: 0.2549019608, green: 0.2549019608, blue: 0.2549019608, alpha: 1),
    
        // TextBox
        .textBox_background: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1),
        .textBox_border: #colorLiteral(red: 0.2549019608, green: 0.2549019608, blue: 0.2549019608, alpha: 1),
    
        // MessageBubble
        .messageBubble_outgoingBackground: .primary,
        .messageBubble_incomingBackground: #colorLiteral(red: 0.1764705882, green: 0.1764705882, blue: 0.1764705882, alpha: 1),
        .messageBubble_outgoingText: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1),
        .messageBubble_incomingText: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1),

        // MenuButton
        .menuButton_background: .primary,
        .menuButton_icon: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1),
        .menuButton_shadow: .primary,
        
        // RadioButton
        .radioButton_selectedBackground: .primary,
        .radioButton_unselectedBackground: .clear,
        .radioButton_selectedBorder: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1),
        .radioButton_unselectedBorder: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1),
        
        // OutlineButton
        .outlineButton_text: .primary,
        .outlineButton_background: .clear,
        .outlineButton_highlight: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 0.3),
        .outlineButton_border: .primary,
        .outlineButton_filledText: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1),
        .outlineButton_filledBackground: #colorLiteral(red: 0.1058823529, green: 0.1058823529, blue: 0.1058823529, alpha: 1),
        .outlineButton_filledHighlight: #colorLiteral(red: 0.2549019608, green: 0.2549019608, blue: 0.2549019608, alpha: 1),
        .outlineButton_destructiveText: #colorLiteral(red: 1, green: 0.2274509804, blue: 0.2274509804, alpha: 1),
        .outlineButton_destructiveBackground: .clear,
        .outlineButton_destructiveHighlight: #colorLiteral(red: 1, green: 0.2274509804, blue: 0.2274509804, alpha: 0.3),
        .outlineButton_destructiveBorder: #colorLiteral(red: 1, green: 0.2274509804, blue: 0.2274509804, alpha: 1),
        
        // Settings
        .settings_tabBackground: #colorLiteral(red: 0.1058823529, green: 0.1058823529, blue: 0.1058823529, alpha: 1),
        .settings_tabHighlight: #colorLiteral(red: 0.2549019608, green: 0.2549019608, blue: 0.2549019608, alpha: 1),
        
        // Appearance
        .appearance_sectionBackground: #colorLiteral(red: 0.1058823529, green: 0.1058823529, blue: 0.1058823529, alpha: 1),
        .appearance_buttonBackground: #colorLiteral(red: 0.1058823529, green: 0.1058823529, blue: 0.1058823529, alpha: 1),
        .appearance_buttonHighlight: #colorLiteral(red: 0.2549019608, green: 0.2549019608, blue: 0.2549019608, alpha: 1),
        
        // ConversationButton
        .conversationButton_background: #colorLiteral(red: 0.1058823529, green: 0.1058823529, blue: 0.1058823529, alpha: 1),
        .conversationButton_highlight: #colorLiteral(red: 0.2549019608, green: 0.2549019608, blue: 0.2549019608, alpha: 1)
    ]
}

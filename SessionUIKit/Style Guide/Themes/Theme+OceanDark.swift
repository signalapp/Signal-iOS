// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIColor

internal enum Theme_OceanDark: ThemeColors {
    static let theme: [ThemeValue: UIColor] = [
        // General
        .primary: .primary,
        .defaultPrimary: Theme.PrimaryColor.blue.color,
        .danger: #colorLiteral(red: 1, green: 0.2274509804, blue: 0.2274509804, alpha: 1),
        .clear: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0),
        .backgroundPrimary: #colorLiteral(red: 0.1450980392, green: 0.1529411765, blue: 0.2078431373, alpha: 1),
        .backgroundSecondary: #colorLiteral(red: 0.1019607843, green: 0.1098039216, blue: 0.1568627451, alpha: 1),
        .textPrimary: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1),
        .textSecondary: #colorLiteral(red: 0.6509803922, green: 0.662745098, blue: 0.8078431373, alpha: 1),
        .borderSeparator: #colorLiteral(red: 0.2392156863, green: 0.2901960784, blue: 0.3647058824, alpha: 1),
    
        // TextBox
        .textBox_background: #colorLiteral(red: 0.1019607843, green: 0.1098039216, blue: 0.1568627451, alpha: 1),
        .textBox_border: #colorLiteral(red: 0.2392156863, green: 0.2901960784, blue: 0.3647058824, alpha: 1),
    
        // MessageBubble
        .messageBubble_outgoingBackground: .primary,
        .messageBubble_incomingBackground: #colorLiteral(red: 0.2392156863, green: 0.2901960784, blue: 0.3647058824, alpha: 1),
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
        .outlineButton_filledBackground: #colorLiteral(red: 0.1019607843, green: 0.1098039216, blue: 0.1568627451, alpha: 1),
        .outlineButton_filledHighlight: #colorLiteral(red: 0.168627451, green: 0.1764705882, blue: 0.2509803922, alpha: 1),
        .outlineButton_destructiveText: #colorLiteral(red: 1, green: 0.2274509804, blue: 0.2274509804, alpha: 1),
        .outlineButton_destructiveBackground: .clear,
        .outlineButton_destructiveHighlight: #colorLiteral(red: 1, green: 0.2274509804, blue: 0.2274509804, alpha: 0.3),
        .outlineButton_destructiveBorder: #colorLiteral(red: 1, green: 0.2274509804, blue: 0.2274509804, alpha: 1),
        
        // Settings
        .settings_tabBackground: #colorLiteral(red: 0.1019607843, green: 0.1098039216, blue: 0.1568627451, alpha: 1),
        .settings_tabHighlight: #colorLiteral(red: 0.168627451, green: 0.1764705882, blue: 0.2509803922, alpha: 1),
        
        // Appearance
        .appearance_sectionBackground: #colorLiteral(red: 0.1019607843, green: 0.1098039216, blue: 0.1568627451, alpha: 1),
        .appearance_buttonBackground: #colorLiteral(red: 0.1019607843, green: 0.1098039216, blue: 0.1568627451, alpha: 1),
        .appearance_buttonHighlight: #colorLiteral(red: 0.168627451, green: 0.1764705882, blue: 0.2509803922, alpha: 1),
        
        // ConversationButton
        .conversationButton_background: #colorLiteral(red: 0.168627451, green: 0.168627451, blue: 0.2509803922, alpha: 1),
        .conversationButton_highlight: #colorLiteral(red: 0.168627451, green: 0.1764705882, blue: 0.2509803922, alpha: 1)
    ]
}

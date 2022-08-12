// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIColor

internal enum Theme_OceanLight: ThemeColors {
    static let theme: [ThemeValue: UIColor] = [
        // General
        .primary: .primary,
        .defaultPrimary: Theme.PrimaryColor.blue.color,
        .danger: #colorLiteral(red: 0.8823529412, green: 0.1764705882, blue: 0.09803921569, alpha: 1),
        .clear: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0),
        .backgroundPrimary: #colorLiteral(red: 0.9882352941, green: 1, blue: 1, alpha: 1),
        .backgroundSecondary: #colorLiteral(red: 0.9254901961, green: 0.9803921569, blue: 0.9843137255, alpha: 1),
        .textPrimary: #colorLiteral(red: 0.09803921569, green: 0.2039215686, blue: 0.3647058824, alpha: 1),
        .textSecondary: #colorLiteral(red: 0.4156862745, green: 0.431372549, blue: 0.5647058824, alpha: 1),
        .borderSeparator: #colorLiteral(red: 0.3607843137, green: 0.6666666667, blue: 0.8, alpha: 1),
    
        // TextBox
        .textBox_background: #colorLiteral(red: 0.9882352941, green: 1, blue: 1, alpha: 1),
        .textBox_border: #colorLiteral(red: 0.3607843137, green: 0.6666666667, blue: 0.8, alpha: 1),
    
        // MessageBubble
        .messageBubble_outgoingBackground: .primary,
        .messageBubble_incomingBackground: #colorLiteral(red: 0.7019607843, green: 0.9294117647, blue: 0.9490196078, alpha: 1),
        .messageBubble_outgoingText: #colorLiteral(red: 0.09803921569, green: 0.2039215686, blue: 0.3647058824, alpha: 1),
        .messageBubble_incomingText: #colorLiteral(red: 0.09803921569, green: 0.2039215686, blue: 0.3647058824, alpha: 1),

        // MenuButton
        .menuButton_background: .primary,
        .menuButton_icon: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1),
        .menuButton_shadow: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1),
        
        // RadioButton
        .radioButton_selectedBackground: .primary,
        .radioButton_unselectedBackground: .clear,
        .radioButton_selectedBorder: #colorLiteral(red: 0.09803921569, green: 0.2039215686, blue: 0.3647058824, alpha: 1),
        .radioButton_unselectedBorder: #colorLiteral(red: 0.3607843137, green: 0.6666666667, blue: 0.8, alpha: 1),
        
        // OutlineButton
        .outlineButton_text: #colorLiteral(red: 0.09803921569, green: 0.2039215686, blue: 0.3647058824, alpha: 1),
        .outlineButton_background: .clear,
        .outlineButton_highlight: #colorLiteral(red: 0.09803921569, green: 0.2039215686, blue: 0.3647058824, alpha: 0.1),
        .outlineButton_border: #colorLiteral(red: 0.09803921569, green: 0.2039215686, blue: 0.3647058824, alpha: 1),
        .outlineButton_filledText: #colorLiteral(red: 0.9882352941, green: 1, blue: 1, alpha: 1),
        .outlineButton_filledBackground: #colorLiteral(red: 0.09803921569, green: 0.2039215686, blue: 0.3647058824, alpha: 1),
        .outlineButton_filledHighlight: #colorLiteral(red: 0.4156862745, green: 0.431372549, blue: 0.5647058824, alpha: 1),
        .outlineButton_destructiveText: #colorLiteral(red: 0.8823529412, green: 0.1764705882, blue: 0.09803921569, alpha: 1),
        .outlineButton_destructiveBackground: .clear,
        .outlineButton_destructiveHighlight: #colorLiteral(red: 0.8823529412, green: 0.1764705882, blue: 0.09803921569, alpha: 0.3),
        .outlineButton_destructiveBorder: #colorLiteral(red: 0.8823529412, green: 0.1764705882, blue: 0.09803921569, alpha: 1),
        
        // Settings
        .settings_tabBackground: #colorLiteral(red: 0.9882352941, green: 1, blue: 1, alpha: 1),
        .settings_tabHighlight: #colorLiteral(red: 0.9058823529, green: 0.9529411765, blue: 0.9568627451, alpha: 1),
        
        // Appearance
        .appearance_sectionBackground: #colorLiteral(red: 0.9882352941, green: 1, blue: 1, alpha: 1),
        .appearance_buttonBackground: #colorLiteral(red: 0.9882352941, green: 1, blue: 1, alpha: 1),
        .appearance_buttonHighlight: #colorLiteral(red: 0.9058823529, green: 0.9529411765, blue: 0.9568627451, alpha: 1),
        
        // ConversationButton
        .conversationButton_background: #colorLiteral(red: 0.9882352941, green: 1, blue: 1, alpha: 1),
        .conversationButton_highlight: #colorLiteral(red: 0.9058823529, green: 0.9529411765, blue: 0.9568627451, alpha: 1)
    ]
}

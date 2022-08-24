// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public final class OutlineButton: UIButton {
    public enum Style {
        case regular
        case borderless
        case destructive
        case filled
    }
    
    public enum Size {
        case small
        case medium
        case large
    }
    
    public init(style: Style, size: Size) {
        super.init(frame: .zero)
        
        setUpStyle(style: style, size: size)
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(style:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(style:) instead.")
    }

    private func setUpStyle(style: Style, size: Size) {
        clipsToBounds = true
        contentEdgeInsets = UIEdgeInsets(
            top: 0,
            left: Values.smallSpacing,
            bottom: 0,
            right: Values.smallSpacing
        )
        titleLabel?.font = .boldSystemFont(ofSize: (size == .small ?
            Values.smallFontSize :
            Values.mediumFontSize
        ))
        setThemeTitleColor(
            {
                switch style {
                    case .regular, .borderless: return .outlineButton_text
                    case .destructive: return .outlineButton_destructiveText
                    case .filled: return .outlineButton_filledText
                }
            }(),
            for: .normal
        )
        
        setThemeBackgroundColor(
            {
                switch style {
                    case .regular, .borderless: return .outlineButton_background
                    case .destructive: return .outlineButton_destructiveBackground
                    case .filled: return .outlineButton_filledBackground
                }
            }(),
            for: .normal
        )
        setThemeBackgroundColor(
            {
                switch style {
                    case .regular, .borderless: return .outlineButton_highlight
                    case .destructive: return .outlineButton_destructiveHighlight
                    case .filled: return .outlineButton_filledHighlight
                }
            }(),
            for: .highlighted
        )
        
        layer.borderWidth = 1
        themeBorderColor = {
            switch style {
                case .regular: return .outlineButton_border
                case .destructive: return .outlineButton_destructiveBorder
                case .filled, .borderless: return nil
            }
        }()
        
        let height: CGFloat = {
            switch size {
                case .small: return Values.smallButtonHeight
                case .medium: return Values.mediumButtonHeight
                case .large: return Values.largeButtonHeight
            }
        }()
        set(.height, to: height)
        layer.cornerRadius = height / 2
    }
}

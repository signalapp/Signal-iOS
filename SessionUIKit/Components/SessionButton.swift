// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public final class SessionButton: UIButton {
    public enum Style {
        case bordered
        case borderless
        case destructive
        case destructiveBorderless
        case filled
    }
    
    public enum Size {
        case small
        case medium
        case large
    }
    
    private let style: Style
    
    public override var isEnabled: Bool {
        didSet {
            guard isEnabled else {
                setThemeTitleColor(
                    {
                        switch style {
                            case .bordered, .borderless, .destructive,
                                .destructiveBorderless:
                                return .disabled
                            
                            case .filled: return .white
                        }
                    }(),
                    for: .normal
                )
                setThemeBackgroundColor(
                    {
                        switch style {
                            case .bordered, .borderless, .destructive,
                                .destructiveBorderless:
                                return .clear
                            
                            case .filled: return .disabled
                        }
                    }(),
                    for: .normal
                )
                setThemeBackgroundColor(nil, for: .highlighted)
                
                themeBorderColor = {
                    switch style {
                        case .bordered, .destructive: return .disabled
                        case .filled, .borderless, .destructiveBorderless: return nil
                    }
                }()
                return
            }
            
            // If we enable the button they just re-apply the existing style
            setup(style: style)
        }
    }
    
    // MARK: - Initialization
    
    public init(style: Style, size: Size) {
        self.style = style
        
        super.init(frame: .zero)
        
        setup(size: size)
        setup(style: style)
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(style:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(style:) instead.")
    }
    
    private func setup(size: Size) {
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
        
        let height: CGFloat = {
            switch size {
                case .small: return Values.smallButtonHeight
                case .medium: return Values.mediumButtonHeight
                case .large: return Values.largeButtonHeight
            }
        }()
        set(.height, to: height)
        layer.cornerRadius = {
            switch style {
                case .borderless, .destructiveBorderless: return 5
                default: return (height / 2)
            }
        }()
    }

    private func setup(style: Style) {
        setThemeTitleColor(
            {
                switch style {
                    case .bordered, .borderless: return .sessionButton_text
                    case .destructive, .destructiveBorderless: return .sessionButton_destructiveText
                    case .filled: return .sessionButton_filledText
                }
            }(),
            for: .normal
        )
        
        setThemeBackgroundColor(
            {
                switch style {
                    case .bordered, .borderless: return .sessionButton_background
                    case .destructive, .destructiveBorderless: return .sessionButton_destructiveBackground
                    case .filled: return .sessionButton_filledBackground
                }
            }(),
            for: .normal
        )
        setThemeBackgroundColor(
            {
                switch style {
                    case .bordered, .borderless: return .sessionButton_highlight
                    case .destructive, .destructiveBorderless: return .sessionButton_destructiveHighlight
                    case .filled: return .sessionButton_filledHighlight
                }
            }(),
            for: .highlighted
        )
        
        layer.borderWidth = {
            switch style {
                case .borderless, .destructiveBorderless: return 0
                default: return 1
            }
        }()
        themeBorderColor = {
            switch style {
                case .bordered: return .sessionButton_border
                case .destructive: return .sessionButton_destructiveBorder
                case .filled, .borderless, .destructiveBorderless: return nil
            }
        }()
    }
}

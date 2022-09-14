// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

final class ScrollToBottomButton: UIView {
    private weak var delegate: ScrollToBottomButtonDelegate?
    
    // MARK: - Settings
    
    private static let size: CGFloat = 40
    private static let iconSize: CGFloat = 16
    
    // MARK: - Lifecycle
    
    init(delegate: ScrollToBottomButtonDelegate) {
        self.delegate = delegate
        
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(delegate:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(delegate:) instead.")
    }
    
    private func setUpViewHierarchy() {
        // Background & blur
        let backgroundView = UIView()
        backgroundView.themeBackgroundColor = .backgroundSecondary
        backgroundView.alpha = Values.lowOpacity
        addSubview(backgroundView)
        backgroundView.pin(to: self)
        
        let blurView = UIVisualEffectView()
        addSubview(blurView)
        blurView.pin(to: self)
        
        ThemeManager.onThemeChange(observer: blurView) { [weak blurView] theme, _ in
            switch theme.interfaceStyle {
                case .light: blurView?.effect = UIBlurEffect(style: .light)
                default: blurView?.effect = UIBlurEffect(style: .dark)
            }
        }
        
        // Size & shape
        set(.width, to: ScrollToBottomButton.size)
        set(.height, to: ScrollToBottomButton.size)
        layer.cornerRadius = (ScrollToBottomButton.size / 2)
        layer.masksToBounds = true
        
        // Border
        self.themeBorderColor = .borderSeparator
        layer.borderWidth = Values.separatorThickness
        
        // Icon
        let iconImageView = UIImageView(
            image: UIImage(named: "ic_chevron_down")?
                .withRenderingMode(.alwaysTemplate)
        )
        iconImageView.themeTintColor = .textPrimary
        iconImageView.contentMode = .scaleAspectFit
        addSubview(iconImageView)
        iconImageView.center(in: self)
        iconImageView.set(.width, to: ScrollToBottomButton.iconSize)
        iconImageView.set(.height, to: ScrollToBottomButton.iconSize)
        
        // Gesture recognizer
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGestureRecognizer)
    }
    
    // MARK: - Interaction
    
    @objc private func handleTap() {
        delegate?.handleScrollToBottomButtonTapped()
    }
}

// MARK: - ScrollToBottomButtonDelegate

protocol ScrollToBottomButtonDelegate: AnyObject {
    func handleScrollToBottomButtonTapped()
}

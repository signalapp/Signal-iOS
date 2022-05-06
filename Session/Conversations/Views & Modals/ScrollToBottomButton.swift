// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

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
        backgroundView.backgroundColor = isLightMode ? .white : .black
        backgroundView.alpha = Values.lowOpacity
        addSubview(backgroundView)
        backgroundView.pin(to: self)
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        addSubview(blurView)
        blurView.pin(to: self)
        // Size & shape
        let size = ScrollToBottomButton.size
        set(.width, to: size)
        set(.height, to: size)
        layer.cornerRadius = size / 2
        layer.masksToBounds = true
        // Border
        layer.borderWidth = Values.separatorThickness
        let borderColor = (isLightMode ? UIColor.black : UIColor.white).withAlphaComponent(Values.veryLowOpacity)
        layer.borderColor = borderColor.cgColor
        // Icon
        let tint = isLightMode ? UIColor.black : UIColor.white
        let icon = UIImage(named: "ic_chevron_down")!.withTint(tint)
        let iconImageView = UIImageView(image: icon)
        iconImageView.set(.width, to: ScrollToBottomButton.iconSize)
        iconImageView.set(.height, to: ScrollToBottomButton.iconSize)
        iconImageView.contentMode = .scaleAspectFit
        addSubview(iconImageView)
        iconImageView.center(in: self)
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

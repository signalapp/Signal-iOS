// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

final class InputViewButton: UIView {
    private let icon: UIImage
    private let isSendButton: Bool
    private weak var delegate: InputViewButtonDelegate?
    private let hasOpaqueBackground: Bool
    private lazy var widthConstraint = set(.width, to: InputViewButton.size)
    private lazy var heightConstraint = set(.height, to: InputViewButton.size)
    private var longPressTimer: Timer?
    private var isLongPress = false
    
    // MARK: - UI Components
    
    private lazy var backgroundView: UIView = UIView()
    private lazy var iconImageView: UIImageView = UIImageView()
    
    // MARK: - Settings
    
    static let size: CGFloat = 40
    static let expandedSize: CGFloat = 48
    static let iconSize: CGFloat = 20
    
    // MARK: - Lifecycle
    
    init(icon: UIImage, isSendButton: Bool = false, delegate: InputViewButtonDelegate, hasOpaqueBackground: Bool = false) {
        self.icon = icon
        self.isSendButton = isSendButton
        self.delegate = delegate
        self.hasOpaqueBackground = hasOpaqueBackground
        
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy()
        self.isAccessibilityElement = true
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(icon:delegate:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(icon:delegate:) instead.")
    }
    
    private func setUpViewHierarchy() {
        themeBackgroundColor = .clear
        
        if hasOpaqueBackground {
            let backgroundView: UIView = UIView()
            backgroundView.themeBackgroundColor = .inputButton_background
            backgroundView.alpha = Values.lowOpacity
            addSubview(backgroundView)
            backgroundView.pin(to: self)
            
            let blurView: UIVisualEffectView = UIVisualEffectView()
            addSubview(blurView)
            blurView.pin(to: self)
            
            ThemeManager.onThemeChange(observer: blurView) { [weak blurView] theme, _ in
                switch theme.interfaceStyle {
                    case .light: blurView?.effect = UIBlurEffect(style: .light)
                    default: blurView?.effect = UIBlurEffect(style: .dark)
                }
            }
            
            themeBorderColor = .borderSeparator
            layer.borderWidth = Values.separatorThickness
        }
        
        backgroundView.themeBackgroundColor = (isSendButton ? .primary : .inputButton_background)
        backgroundView.alpha = (isSendButton ? 1 : Values.lowOpacity)
        addSubview(backgroundView)
        backgroundView.pin(to: self)
        
        layer.cornerRadius = (InputViewButton.size / 2)
        layer.masksToBounds = true
        isUserInteractionEnabled = true
        widthConstraint.isActive = true
        heightConstraint.isActive = true
        
        iconImageView.image = icon.withRenderingMode(.alwaysTemplate)
        iconImageView.themeTintColor = (isSendButton ? .black : .textPrimary)
        iconImageView.contentMode = .scaleAspectFit
        addSubview(iconImageView)
        iconImageView.center(in: self)
        iconImageView.set(.width, to: InputViewButton.iconSize)
        iconImageView.set(.height, to: InputViewButton.iconSize)
    }
    
    // MARK: - Animation
    
    private func animate(
        to size: CGFloat,
        themeBackgroundColor: ThemeValue,
        themeTintColor: ThemeValue,
        alpha: CGFloat
    ) {
        let frame = CGRect(center: center, size: CGSize(width: size, height: size))
        widthConstraint.constant = size
        heightConstraint.constant = size
        
        UIView.animate(withDuration: 0.25) {
            self.layoutIfNeeded()
            self.frame = frame
            self.layer.cornerRadius = (size / 2)
            self.iconImageView.themeTintColor = themeTintColor
            self.backgroundView.themeBackgroundColor = themeBackgroundColor
            self.backgroundView.alpha = alpha
        }
    }
    
    private func expand() {
        animate(
            to: InputViewButton.expandedSize,
            themeBackgroundColor: .primary,
            themeTintColor: .black,
            alpha: 1
        )
    }
    
    private func collapse() {
        animate(
            to: InputViewButton.size,
            themeBackgroundColor: (isSendButton ? .primary : .inputButton_background),
            themeTintColor: (isSendButton ? .black : .textPrimary),
            alpha: (isSendButton ? 1 : Values.lowOpacity)
        )
    }
    
    // MARK: - Interaction
    
    // We want to detect both taps and long presses
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isUserInteractionEnabled else { return }
        
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        expand()
        invalidateLongPressIfNeeded()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false, block: { [weak self] _ in
            self?.isLongPress = true
            self?.delegate?.handleInputViewButtonLongPressBegan(self)
        })
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isUserInteractionEnabled else { return }
        
        if isLongPress {
            delegate?.handleInputViewButtonLongPressMoved(self, with: touches.first)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isUserInteractionEnabled else { return }
        
        collapse()
        if !isLongPress {
            delegate?.handleInputViewButtonTapped(self)
        } else {
            delegate?.handleInputViewButtonLongPressEnded(self, with: touches.first)
        }
        invalidateLongPressIfNeeded()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        collapse()
        invalidateLongPressIfNeeded()
    }

    private func invalidateLongPressIfNeeded() {
        longPressTimer?.invalidate()
        isLongPress = false
    }
}

// MARK: - Delegate

protocol InputViewButtonDelegate: AnyObject {
    func handleInputViewButtonTapped(_ inputViewButton: InputViewButton)
    func handleInputViewButtonLongPressBegan(_ inputViewButton: InputViewButton?)
    func handleInputViewButtonLongPressMoved(_ inputViewButton: InputViewButton, with touch: UITouch?)
    func handleInputViewButtonLongPressEnded(_ inputViewButton: InputViewButton, with touch: UITouch?)
}

extension InputViewButtonDelegate {    
    func handleInputViewButtonLongPressBegan(_ inputViewButton: InputViewButton?) { }
    func handleInputViewButtonLongPressMoved(_ inputViewButton: InputViewButton, with touch: UITouch?) { }
    func handleInputViewButtonLongPressEnded(_ inputViewButton: InputViewButton, with touch: UITouch?) { }
}

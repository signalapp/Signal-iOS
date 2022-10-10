// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

public final class InputTextView: UITextView, UITextViewDelegate {
    private weak var snDelegate: InputTextViewDelegate?
    private let maxWidth: CGFloat
    private lazy var heightConstraint = self.set(.height, to: minHeight)
    
    public override var text: String? { didSet { handleTextChanged() } }
    
    // MARK: - UI Components
    
    private lazy var placeholderLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.text = "vc_conversation_input_prompt".localized()
        result.themeTextColor = .textSecondary
        
        return result
    }()
    
    // MARK: - Settings
    
    private let minHeight: CGFloat = 22
    private let maxHeight: CGFloat = 80

    // MARK: - Lifecycle
    
    init(delegate: InputTextViewDelegate, maxWidth: CGFloat) {
        snDelegate = delegate
        self.maxWidth = maxWidth
        
        super.init(frame: CGRect.zero, textContainer: nil)
        
        setUpViewHierarchy()
        self.delegate = self
        self.isAccessibilityElement = true
        self.accessibilityLabel = "vc_conversation_input_prompt".localized()
    }
    
    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        preconditionFailure("Use init(delegate:) instead.")
    }

    public required init?(coder: NSCoder) {
        preconditionFailure("Use init(delegate:) instead.")
    }
    
    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            if let _ = UIPasteboard.general.image {
                return true
            }
        }
        return super.canPerformAction(action, withSender: sender)
    }
    
    public override func paste(_ sender: Any?) {
        if let image = UIPasteboard.general.image {
            snDelegate?.didPasteImageFromPasteboard(self, image: image)
        }
        super.paste(sender)
    }

    private func setUpViewHierarchy() {
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        
        font = .systemFont(ofSize: Values.mediumFontSize)
        themeBackgroundColor = .clear
        themeTextColor = .textPrimary
        themeTintColor = .primary
        
        heightConstraint.isActive = true
        let horizontalInset: CGFloat = 2
        textContainerInset = UIEdgeInsets(top: 0, left: horizontalInset, bottom: 0, right: horizontalInset)
        addSubview(placeholderLabel)
        placeholderLabel.pin(.leading, to: .leading, of: self, withInset: horizontalInset + 3) // Slight visual adjustment
        placeholderLabel.pin(.top, to: .top, of: self)
        pin(.trailing, to: .trailing, of: placeholderLabel, withInset: horizontalInset)
        pin(.bottom, to: .bottom, of: placeholderLabel)
        
        ThemeManager.onThemeChange(observer: self) { [weak self] theme, _ in
            switch theme.interfaceStyle {
                case .light: self?.keyboardAppearance = .light
                default: self?.keyboardAppearance = .dark
            }
        }
    }

    // MARK: - Updating
    
    public func textViewDidChange(_ textView: UITextView) {
        handleTextChanged()
    }
    
    private func handleTextChanged() {
        defer { snDelegate?.inputTextViewDidChangeContent(self) }
        
        placeholderLabel.isHidden = !(text ?? "").isEmpty
        
        let height = frame.height
        let size = sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        
        // `textView.contentSize` isn't accurate when restoring a multiline draft, so we set it here manually
        self.contentSize = size
        let newHeight = size.height.clamp(minHeight, maxHeight)
        
        guard newHeight != height else { return }
        
        heightConstraint.constant = newHeight
        snDelegate?.inputTextViewDidChangeSize(self)
    }
}

// MARK: - InputTextViewDelegate

protocol InputTextViewDelegate: AnyObject {
    func inputTextViewDidChangeSize(_ inputTextView: InputTextView)
    func inputTextViewDidChangeContent(_ inputTextView: InputTextView)
    func didPasteImageFromPasteboard(_ inputTextView: InputTextView, image: UIImage)
}

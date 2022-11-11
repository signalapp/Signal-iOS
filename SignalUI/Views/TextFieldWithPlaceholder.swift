//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol TextFieldWithPlaceholderDelegate: AnyObject {

    func textFieldDidBeginEditing(_ textField: UITextField)

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool
}

// MARK: -

public class TextFieldWithPlaceholder: UIView {

    // MARK: - Public Properties

    public weak var delegate: TextFieldWithPlaceholderDelegate?

    public var placeholderText: String = "" {
        didSet {
            placeholderLabel.text = placeholderText
            textfield.accessibilityLabel = placeholderText
        }
    }

    public func acceptAutocorrectSuggestion() {
        textfield.acceptAutocorrectSuggestion()
    }

    public var text: String? {
        get { textfield.text?.nilIfEmpty }
        set {
            textfield.text = newValue
            updatePlaceholderVisibility()
        }
    }

    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        textfield.becomeFirstResponder()
    }

    @discardableResult
    public override func resignFirstResponder() -> Bool {
        textfield.resignFirstResponder()
    }

    public override var canBecomeFirstResponder: Bool {
        textfield.canBecomeFirstResponder
    }

    public override var isFirstResponder: Bool {
        textfield.isFirstResponder
    }

    public var font: UIFont? {
        get { textfield.font }
        set { textfield.font = newValue }
    }

    // MARK: - Private Properties

    private lazy var textfield = UITextField()
    private lazy var placeholderLabel = UILabel()

    // MARK: - Lifecycle

    public override init(frame: CGRect) {
        super.init(frame: frame)
        applyTheme()

        textfield.delegate = self
        placeholderLabel.isUserInteractionEnabled = false

        // The placeholderLabel is perfectly aligned with the textView to allow for us to easily
        // hide/show placeholder text without needing to manipulate the text property of our primary
        // text view. This makes VoiceOver navigation by dragging a bit tricky, since a user won't be
        // able to find the placeholder text. Let's disable it in VoiceOver. Instead, placeholderText
        // will be an accessibility label on the primary text view.
        placeholderLabel.accessibilityElementsHidden = true

        // Layout + Constraints
        for subview in [textfield, placeholderLabel] {
            addSubview(subview)
            subview.autoPinEdgesToSuperviewEdges()
            subview.setCompressionResistanceHigh()
        }

        textfield.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .ThemeDidChange, object: nil)

        updatePlaceholderVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    @objc
    private func textFieldDidChange(sender: UITextField) {
        Logger.info("")

        updatePlaceholderVisibility()
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = text != nil
    }

    // MARK: - Private

    @objc
    private func applyTheme() {
        placeholderLabel.textColor = Theme.placeholderColor
        textfield.textColor = Theme.primaryTextColor
    }
}

// MARK: -

extension TextFieldWithPlaceholder: UITextFieldDelegate {
    public func textFieldDidBeginEditing(_ textField: UITextField) {
        delegate?.textFieldDidBeginEditing(textField)
    }

    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        delegate?.textField(textField, shouldChangeCharactersIn: range, replacementString: string) ?? true
    }
}

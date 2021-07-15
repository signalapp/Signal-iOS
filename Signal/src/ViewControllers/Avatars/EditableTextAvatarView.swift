//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public protocol EditableTextAvatarDelegate: AnyObject {
    func editableTextAvatarViewDidFinishEditing()
}

public class EditableTextAvatarView: UIView {
    public var theme: AvatarTheme { didSet { updateTheme() }}
    public var text: String? {
        get { textField.text }
        set { textField.text = newValue }
    }

    public weak var delegate: EditableTextAvatarDelegate?

    private let textField = UITextField()

    public init(theme: AvatarTheme, text: AvatarText) {
        self.theme = theme
        self.textField.text = text.text
        super.init(frame: .zero)

        textField.textAlignment = .center

        textField.adjustsFontSizeToFitWidth = true
        textField.contentScaleFactor = 0.75
        textField.returnKeyType = .done
        textField.delegate = self

        addSubview(textField)
        textField.autoCenterInSuperview()

        updateTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    public override func becomeFirstResponder() -> Bool { textField.becomeFirstResponder() }
    public override func resignFirstResponder() -> Bool { textField.resignFirstResponder() }
    public override var canBecomeFirstResponder: Bool { textField.canBecomeFirstResponder }
    public override var isFirstResponder: Bool { textField.isFirstResponder }

    public override func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = height / 2

        // We use the "Inter" font for text based avatars, so they look
        // the same across all platforms. The font is scaled relative to
        // the height of the avatar.
        textField.font = UIFont(name: "Inter", size: height * 0.42)
    }

    // MARK: -

    func updateTheme() {
        backgroundColor = theme.backgroundColor
        textField.textColor = theme.foregroundColor
    }
}

extension EditableTextAvatarView: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        TextFieldHelper.textField(textField, shouldChangeCharactersInRange: range, replacementString: string, maxGlyphCount: 3)
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        delegate?.editableTextAvatarViewDidFinishEditing()
        return false
    }
}

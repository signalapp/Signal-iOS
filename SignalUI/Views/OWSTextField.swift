//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

open class OWSTextField: UITextField {
    override public init(frame: CGRect) {
        super.init(frame: frame)
        self.disableAiWritingTools()
        applyTheme()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.disableAiWritingTools()
        applyTheme()
    }

    public convenience init(
        font: UIFont = .dynamicTypeBody,
        placeholder: String? = nil,
        keyboardType: UIKeyboardType = .default,
        returnKeyType: UIReturnKeyType = .default,
        spellCheckingType: UITextSpellCheckingType = .default,
        autocorrectionType: UITextAutocorrectionType = .default,
        // .sentences is default for UITextField
        autocapitalizationType: UITextAutocapitalizationType = .sentences,
        clearButtonMode: UITextField.ViewMode = .never,
        delegate: UITextFieldDelegate? = nil,
        editingChanged: (() -> Void)? = nil,
        returnPressed: (() -> Void)? = nil,
    ) {
        self.init(frame: .zero)
        self.font = font
        self.placeholder = placeholder
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.spellCheckingType = spellCheckingType
        self.autocorrectionType = autocorrectionType
        self.autocapitalizationType = autocapitalizationType
        self.clearButtonMode = clearButtonMode
        self.delegate = delegate
        if let editingChanged {
            self.addAction(UIAction { _ in editingChanged() }, for: .editingChanged)
        }
        if let returnPressed {
            self.addAction(UIAction { _ in returnPressed() }, for: .editingDidEndOnExit)
        }
    }

    private func applyTheme() {
        keyboardAppearance = Theme.keyboardAppearance
    }
}

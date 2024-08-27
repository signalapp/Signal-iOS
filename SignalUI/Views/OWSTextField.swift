//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

open class OWSTextField: UITextField {
    public override init(frame: CGRect) {
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
        returnPressed: (() -> Void)? = nil
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
            self.editingChangedAction = editingChanged
            self.addTarget(self, action: #selector(self.editingChanged), for: .editingChanged)
        }
        if let returnPressed {
            self.returnPressedAction = returnPressed
            self.addTarget(self, action: #selector(self.returnPressed), for: .editingDidEndOnExit)
        }
    }

    private func applyTheme() {
        keyboardAppearance = Theme.keyboardAppearance
    }

    // MARK: Editing changed

    private var editingChangedAction: (() -> Void)?

    @objc
    private func editingChanged() {
        self.editingChangedAction?()
    }

    // MARK: Return pressed

    private var returnPressedAction: (() -> Void)?

    @objc
    private func returnPressed() {
        self.returnPressedAction?()
    }
}

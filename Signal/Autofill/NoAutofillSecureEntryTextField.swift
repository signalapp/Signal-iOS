//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

/// A `UITextField` with `isSecureTextEntry` enabled that prevents Authentication
/// Services from offering to autofill passwords.
///
/// Authentication Services provides Password AutoFill, which uses opaque
/// heuristics informed by things like `isSecureTextEntry` and `textContentType`
/// to "intelligently" suggest things like autofilling a password from your
/// password manager or generating a throwaway email. Notably, the heuristics
/// unequivocally suggest autofilling if `isSecureEntry = true` on iOS 26.
///
/// This type manipulates those heuristics to let us set `isSecureEntry = true`
/// while avoiding AutoFill suggestions.
final class NoAutofillSecureEntryTextField: UITextField {
    private var warnWhenSettingSecureTextEntry: Bool = true

    override var isSecureTextEntry: Bool {
        didSet {
            if warnWhenSettingSecureTextEntry {
                owsFailDebug("Do not manually set isSecureTextEntry on this type!")
            }
        }
    }

    override var textContentType: UITextContentType? {
        didSet {
            owsFailDebug("Do not manually set textContentType on this type!")
        }
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return performAvoidingAutofill {
            return super.becomeFirstResponder()
        }
    }

    override func reloadInputViews() {
        performAvoidingAutofill {
            super.reloadInputViews()
        }
    }

    private func performAvoidingAutofill<T>(_ block: () -> T) -> T {
        defer {
            DispatchQueue.main.async { [weak self] in
                self?.setIsSecureTextEntry(true)
            }
        }

        setIsSecureTextEntry(false)
        return block()
    }

    private func setIsSecureTextEntry(_ isSecureTextEntry: Bool) {
        warnWhenSettingSecureTextEntry = false
        self.isSecureTextEntry = isSecureTextEntry
        warnWhenSettingSecureTextEntry = true
    }
}

//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

open class RecipientPickerContainerViewController: OWSViewController {
    public let recipientPicker = RecipientPickerViewController()

    private var didApplyTheme = false

    open override func themeDidChange() {
        super.themeDidChange()
        if didApplyTheme {
            recipientPicker.applyTheme(to: self)
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        recipientPicker.applyTheme(to: self)
        didApplyTheme = true
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        recipientPicker.removeTheme(from: self)
        didApplyTheme = false
    }
}

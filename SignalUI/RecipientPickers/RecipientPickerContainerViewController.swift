//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

open class RecipientPickerContainerViewController: OWSViewController, OWSNavigationChildController {
    public let recipientPicker = RecipientPickerViewController()

    open override func themeDidChange() {
        super.themeDidChange()
        if lifecycle == .willAppear || lifecycle == .appeared {
            recipientPicker.applyTheme(to: self)
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        recipientPicker.applyTheme(to: self)
    }

    public var childForOWSNavigationConfiguration: OWSNavigationChildController? {
        return recipientPicker
    }
}

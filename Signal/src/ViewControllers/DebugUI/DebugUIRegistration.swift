//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUIRegistration: DebugUIPage {
    let name = "Registration UI"
    private var presenter: RegistrationTwoFactorAuthenticatorCodePresenter?

    func section(thread: TSThread?) -> OWSTableSection? {
        var items = [OWSTableItem]()
        items += [
            OWSTableItem.disclosureItem(
                withText: "Two-Factor Code Entry",
                actionBlock: {
                    let presenter = DebugRegistrationTwoFactorAuthenticatorCodePresenter()
                    self.presenter = presenter
                    let viewController = RegistrationTwoFactorAuthenticatorCodeViewController(presenter: presenter)
                    UIApplication.shared.frontmostViewController?
                        .navigationController?
                        .pushViewController(viewController, animated: true)
                },
            ),
        ]
        return OWSTableSection(title: name, items: items)
    }
}

private class DebugRegistrationTwoFactorAuthenticatorCodePresenter: RegistrationTwoFactorAuthenticatorCodePresenter {
    func submitAuthenticatorCode(_ code: String) {
        UIApplication.shared.frontmostViewController?
            .navigationController?
            .topViewController?
            .presentToast(text: "Entered code: \(code)")
    }

    func cancelTwoFactorAuth() {
        UIApplication.shared.frontmostViewController?
            .navigationController?
            .topViewController?
            .dismiss(animated: true)
    }
}

#endif

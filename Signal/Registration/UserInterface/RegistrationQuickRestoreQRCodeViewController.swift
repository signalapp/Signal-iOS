//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

protocol RegistrationMethodPresenter: AnyObject {
    func cancelChosenRestoreMethod()
}

protocol RegistrationQuickRestoreQRCodePresenter: RegistrationMethodPresenter {
    func didReceiveRegistrationMessage(_ message: RegistrationProvisioningMessage)
}

class RegistrationQuickRestoreQRCodeViewController: BaseQuickRestoreQRCodeViewController {
    private weak var presenter: RegistrationQuickRestoreQRCodePresenter?

    init(presenter: RegistrationQuickRestoreQRCodePresenter) {
        self.presenter = presenter
        super.init()
    }

    override func cancel() {
        super.cancel()
        presenter?.cancelChosenRestoreMethod()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Task {
            do {
                let message = try await waitForMessage()
                presenter?.didReceiveRegistrationMessage(message)
            } catch {
                let title = OWSLocalizedString(
                    "REGISTRATION_SCAN_QR_CODE_FAILED_TITLE",
                    comment: "Title of error notifying restore failed.",
                )
                let body = OWSLocalizedString(
                    "REGISTRATION_SCAN_QR_CODE_FAILED_BODY",
                    comment: "Body of error notifying restore failed.",
                )
                let sheet = HeroSheetViewController(
                    hero: .circleIcon(
                        icon: .alert,
                        iconSize: 36,
                        tintColor: UIColor.Signal.label,
                        backgroundColor: UIColor.Signal.background,
                    ),
                    title: title,
                    body: body,
                    primaryButton: .init(title: CommonStrings.okayButton, action: { [weak self] _ in
                        self?.reset()
                        self?.presentedViewController?.dismiss(animated: true)
                    }),
                )
                present(sheet, animated: true)
            }
        }
    }
}

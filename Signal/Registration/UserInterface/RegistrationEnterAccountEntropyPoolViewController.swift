//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

protocol RegistrationEnterAccountEntropyPoolPresenter: AnyObject {
    func next(accountEntropyPool: AccountEntropyPool)
    func cancelKeyEntry()
}

class RegistrationEnterAccountEntropyPoolViewController: EnterAccountEntropyPoolViewController {
    private weak var presenter: RegistrationEnterAccountEntropyPoolPresenter?

    init(presenter: RegistrationEnterAccountEntropyPoolPresenter) {
        self.presenter = presenter

        super.init()

        configure(
            aepValidationPolicy: .acceptAnyWellFormed,
            colorConfig: ColorConfig(
                background: UIColor.Signal.background,
                aepEntryBackground: UIColor.Signal.quaternaryFill,
            ),
            headerStrings: HeaderStrings(
                title: OWSLocalizedString(
                    "REGISTRATION_ENTER_BACKUP_KEY_TITLE",
                    comment: "Title for the screen that allows users to enter their backup key."
                ),
                subtitle: OWSLocalizedString(
                    "REGISTRATION_ENTER_BACKUP_KEY_DESCRIPTION",
                    comment: "Description for the screen that allows users to enter their backup key."
                )
            ),
            footerButtonConfig: FooterButtonConfig(
                title: OWSLocalizedString(
                    "REGISTRATION_NO_BACKUP_KEY_BUTTON_TITLE",
                    comment: "Title of button to tap if you do not have a backup key during registration."
                ),
                action: { [weak self] in
                    self?.didTapNoKeyButton()
                },
            ),
            onEntryConfirmed: { [weak self] aep in
                self?.presenter?.next(accountEntropyPool: aep)
            },
        )

        navigationItem.leftBarButtonItem = .button(title: CommonStrings.backButton, style: .done) { [weak self] in
            self?.presenter?.cancelKeyEntry()
        }
    }

    // MARK: OWSNavigationChildController

    public var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }

    public var navbarBackgroundColorOverride: UIColor? { .clear }

    // MARK: UI

    private func didTapNoKeyButton() {
        let sheet = HeroSheetViewController(
            hero: .circleIcon(
                icon: UIImage(named: "key")!,
                iconSize: 35,
                tintColor: UIColor.Signal.label,
                backgroundColor: UIColor.Signal.background
            ),
            title: OWSLocalizedString(
                "REGISTRATION_NO_BACKUP_KEY_SHEET_TITLE",
                comment: "Title for sheet with info for what to do if you don't have a backup key"
            ),
            body: OWSLocalizedString(
                "REGISTRATION_NO_BACKUP_KEY_SHEET_BODY",
                comment: "Body text on a sheet with info for what to do if you don't have a backup key"
            ),
            primaryButton: .init(title: OWSLocalizedString(
                "REGISTRATION_NO_BACKUP_KEY_SKIP_RESTORE_BUTTON_TITLE",
                comment: "Title for button on sheet for when you don't have a backup key"
            )) { [weak self] _ in
                // [Backups] TODO: Implement
                self?.dismiss(animated: true)
            },
            secondaryButton: .init(title: CommonStrings.learnMore) { [weak self] _ in
                // [Backups] TODO: Implement
                self?.dismiss(animated: true)
            }
        )
        self.present(sheet, animated: true)
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationEnterAccountEntropyPoolPresenter: RegistrationEnterAccountEntropyPoolPresenter {
    func next(accountEntropyPool: AccountEntropyPool) {
        print("next")
    }

    func cancelKeyEntry() {
        print("cancel")
    }
}

@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationEnterAccountEntropyPoolPresenter()
    return UINavigationController(
        rootViewController: RegistrationEnterAccountEntropyPoolViewController(
            presenter: presenter
        )
    )
}

#endif

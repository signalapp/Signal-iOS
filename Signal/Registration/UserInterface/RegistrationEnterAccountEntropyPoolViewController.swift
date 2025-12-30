//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI
import SwiftUI

protocol RegistrationEnterAccountEntropyPoolPresenter: AnyObject {
    func next(accountEntropyPool: AccountEntropyPool)
    func cancelKeyEntry()
    func forgotKeyAction()
}

public struct RegistrationEnterAccountEntropyPoolState: Equatable {
    let canShowBackButton: Bool
    let canShowNoKeyHelpButton: Bool
}

class RegistrationEnterAccountEntropyPoolViewController: EnterAccountEntropyPoolViewController, OWSNavigationChildController {
    private weak var presenter: RegistrationEnterAccountEntropyPoolPresenter?
    private let state: RegistrationEnterAccountEntropyPoolState

    init(
        state: RegistrationEnterAccountEntropyPoolState,
        presenter: RegistrationEnterAccountEntropyPoolPresenter,
        aepValidationPolicy: AEPValidationPolicy = .acceptAnyWellFormed,
    ) {
        self.state = state
        self.presenter = presenter

        super.init()

        var footerButtonConfig: FooterButtonConfig?
        if state.canShowNoKeyHelpButton {
            footerButtonConfig = FooterButtonConfig(
                title: OWSLocalizedString(
                    "REGISTRATION_NO_BACKUP_KEY_BUTTON_TITLE",
                    comment: "Title of button to tap if you do not have a recovery key during registration.",
                ),
                action: { [weak self] in
                    self?.didTapNoKeyButton()
                },
            )
        }

        switch aepValidationPolicy {
        case .acceptAnyWellFormed:
            break
        case .acceptOnly:
            footerButtonConfig = FooterButtonConfig(
                title: OWSLocalizedString(
                    "BACKUP_KEY_REMINDER_FORGOT_KEY",
                    comment: "Title of button to tap if you forgot your recovery key.",
                ),
                action: {
                    presenter.forgotKeyAction()
                },
            )
        }

        configure(
            aepValidationPolicy: aepValidationPolicy,
            colorConfig: ColorConfig(
                background: UIColor.Signal.background,
                aepEntryBackground: UIColor.Signal.quaternaryFill,
            ),
            headerStrings: HeaderStrings(
                title: OWSLocalizedString(
                    "REGISTRATION_ENTER_BACKUP_KEY_TITLE",
                    comment: "Title for the screen that allows users to enter their recovery key.",
                ),
                subtitle: OWSLocalizedString(
                    "REGISTRATION_ENTER_BACKUP_KEY_DESCRIPTION",
                    comment: "Description for the screen that allows users to enter their recovery key.",
                ),
            ),
            footerButtonConfig: footerButtonConfig,
            onEntryConfirmed: { [weak self] aep in
                self?.presenter?.next(accountEntropyPool: aep)
            },
        )

        if state.canShowBackButton {
            navigationItem.leftBarButtonItem = .button(title: CommonStrings.backButton, style: .done) { [weak self] in
                self?.presenter?.cancelKeyEntry()
            }
        } else {
            navigationItem.hidesBackButton = true
        }
    }

    // MARK: OWSNavigationChildController

    var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }

    var navbarBackgroundColorOverride: UIColor? { .clear }

    // MARK: UI

    private func didTapNoKeyButton() {
        let sheet = HeroSheetViewController(
            hero: .circleIcon(
                icon: UIImage(named: "key")!,
                iconSize: 35,
                tintColor: UIColor.Signal.label,
                backgroundColor: UIColor.Signal.background,
            ),
            title: OWSLocalizedString(
                "REGISTRATION_NO_BACKUP_KEY_SHEET_TITLE",
                comment: "Title for sheet with info for what to do if you don't have a recovery key",
            ),
            body: OWSLocalizedString(
                "REGISTRATION_NO_BACKUP_KEY_SHEET_BODY",
                comment: "Body text on a sheet with info for what to do if you don't have a recovery key",
            ),
            primaryButton: .init(title: OWSLocalizedString(
                "REGISTRATION_NO_BACKUP_KEY_SKIP_RESTORE_BUTTON_TITLE",
                comment: "Title for button on sheet for when you don't have a recovery key",
            )) { [weak self] _ in
                self?.dismiss(animated: true) {
                    self?.presenter?.forgotKeyAction()
                }
            },
            secondaryButton: .init(title: CommonStrings.learnMore, style: .secondary, action: .custom({ [weak self] sheet in
                guard let self else { return }
                let vc = SFSafariViewController(url: URL.Support.backups)
                self.dismiss(animated: true) {
                    self.present(vc, animated: true, completion: nil)
                }
            })),
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

    func forgotKeyAction() {
        print("forgotKeyAction")
    }
}

@available(iOS 17, *)
#Preview("Default") {
    let presenter = PreviewRegistrationEnterAccountEntropyPoolPresenter()
    return UINavigationController(
        rootViewController: RegistrationEnterAccountEntropyPoolViewController(
            state: RegistrationEnterAccountEntropyPoolState(
                canShowBackButton: true,
                canShowNoKeyHelpButton: true,
            ),
            presenter: presenter,
        ),
    )
}

@available(iOS 17, *)
#Preview("No Help") {
    let presenter = PreviewRegistrationEnterAccountEntropyPoolPresenter()
    return UINavigationController(
        rootViewController: RegistrationEnterAccountEntropyPoolViewController(
            state: RegistrationEnterAccountEntropyPoolState(
                canShowBackButton: true,
                canShowNoKeyHelpButton: false,
            ),
            presenter: presenter,
        ),
    )
}

#endif

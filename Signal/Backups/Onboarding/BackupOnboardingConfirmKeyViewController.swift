//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BackupOnboardingConfirmKeyViewController: EnterAccountEntropyPoolViewController {
    private let aep: AccountEntropyPool

    init(
        aep: AccountEntropyPool,
        onContinue: @escaping () -> Void,
        onSeeKeyAgain: @escaping () -> Void,
    ) {
        self.aep = aep

        super.init()

        configure(
            aepValidationPolicy: .acceptOnly(aep),
            colorConfig: ColorConfig(
                background: UIColor.Signal.groupedBackground,
                aepEntryBackground: UIColor.Signal.secondaryGroupedBackground,
            ),
            headerStrings: HeaderStrings(
                title: OWSLocalizedString(
                    "BACKUP_ONBOARDING_CONFIRM_KEY_TITLE",
                    comment: "Title for a view asking users to confirm their 'Backup Key'."
                ),
                subtitle: OWSLocalizedString(
                    "BACKUP_ONBOARDING_CONFIRM_KEY_SUBTITLE",
                    comment: "Subtitle for a view asking users to confirm their 'Backup Key'."
                )
            ),
            footerButtonConfig: FooterButtonConfig(
                title: seeKeyAgainButtonTitle,
                action: {
                    onSeeKeyAgain()
                }
            ),
            onEntryConfirmed: { [weak self] aep in
                self?.showKeepKeySafeSheet(
                    onContinue: onContinue,
                    onSeeKeyAgain: onSeeKeyAgain
                )
            }
        )
    }

    private var seeKeyAgainButtonTitle: String {
        return OWSLocalizedString(
            "BACKUP_ONBOARDING_CONFIRM_KEY_SEE_KEY_AGAIN_BUTTON_TITLE",
            comment: "Title for a button offering to let users see their 'Backup Key'."
        )
    }

    private func showKeepKeySafeSheet(
        onContinue: @escaping () -> Void,
        onSeeKeyAgain: @escaping () -> Void,
    ) {
        let sheet = HeroSheetViewController(
            hero: .image(.backupsKey),
            title: OWSLocalizedString(
                "BACKUP_ONBOARDING_CONFIRM_KEY_KEEP_KEY_SAFE_SHEET_TITLE",
                comment: "Title for a sheet warning users to their 'Backup Key' safe."
            ),
            body: OWSLocalizedString(
                "BACKUP_ONBOARDING_CONFIRM_KEY_KEEP_KEY_SAFE_SHEET_BODY",
                comment: "Body for a sheet warning users to their 'Backup Key' safe."
            ),
            primaryButton: HeroSheetViewController.Button(
                title: CommonStrings.continueButton,
                action: { sheet in
                    sheet.dismiss(animated: true) {
                        onContinue()
                    }
                }
            ),
            secondaryButton: HeroSheetViewController.Button(
                title: seeKeyAgainButtonTitle,
                style: .secondary,
                action: .custom({ sheet in
                    sheet.dismiss(animated: true) {
                        onSeeKeyAgain()
                    }
                }),
            )
        )

        present(sheet, animated: true)
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    let aep = try! AccountEntropyPool(key: String(
        repeating: "a",
        count: AccountEntropyPool.Constants.byteLength
    ))

    return UINavigationController(
        rootViewController: BackupOnboardingConfirmKeyViewController(
            aep: aep,
            onContinue: { print("Continuing...!") },
            onSeeKeyAgain: { print("Seeing key again...!") }
        )
    )
}

#endif

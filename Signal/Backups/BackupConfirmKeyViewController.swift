//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BackupConfirmKeyViewController: EnterAccountEntropyPoolViewController, OWSNavigationChildController {
    private let aep: AccountEntropyPool

    private let onBackPressed: (() -> Void)?
    var shouldCancelNavigationBack: Bool {
        onBackPressed != nil
    }

    init(
        aep: AccountEntropyPool,
        onContinue: @escaping (BackupConfirmKeyViewController) -> Void,
        onSeeKeyAgain: @escaping () -> Void,
        onBackPressed: (() -> Void)? = nil,
    ) {
        self.aep = aep
        self.onBackPressed = onBackPressed

        super.init()

        OWSTableViewController2.removeBackButtonText(viewController: self)

        if let onBackPressed {
            navigationItem.hidesBackButton = true
            navigationItem.leftBarButtonItem = .init(
                image: UIImage(named: "chevron-left-bold-28"),
                primaryAction: UIAction { _ in
                    onBackPressed()
                },
            )

            isModalInPresentation = true
        }

        configure(
            aepValidationPolicy: .acceptOnly(aep),
            colorConfig: ColorConfig(
                background: UIColor.Signal.groupedBackground,
                aepEntryBackground: UIColor.Signal.secondaryGroupedBackground,
            ),
            headerStrings: HeaderStrings(
                title: OWSLocalizedString(
                    "BACKUP_ONBOARDING_CONFIRM_KEY_TITLE",
                    comment: "Title for a view asking users to confirm their 'Recovery Key'.",
                ),
                subtitle: OWSLocalizedString(
                    "BACKUP_ONBOARDING_CONFIRM_KEY_SUBTITLE",
                    comment: "Subtitle for a view asking users to confirm their 'Recovery Key'.",
                ),
            ),
            footerButtonConfig: FooterButtonConfig(
                title: BackupKeepKeySafeSheet.seeKeyAgainButtonTitle,
                action: {
                    onSeeKeyAgain()
                },
            ),
            onEntryConfirmed: { [weak self] aep in
                guard let self else { return }

                present(
                    BackupKeepKeySafeSheet(
                        onContinue: { onContinue(self) },
                        onSeeKeyAgain: onSeeKeyAgain,
                    ),
                    animated: true,
                )
            },
        )
    }

    // MARK: OWSNavigationChildController

    var navbarBackgroundColorOverride: UIColor? {
        .Signal.groupedBackground
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    let aep = try! AccountEntropyPool(key: String(
        repeating: "a",
        count: AccountEntropyPool.Constants.byteLength,
    ))

    return UINavigationController(
        rootViewController: BackupConfirmKeyViewController(
            aep: aep,
            onContinue: { _ in print("Continuing...!") },
            onSeeKeyAgain: { print("Seeing key again...!") },
        ),
    )
}

#endif

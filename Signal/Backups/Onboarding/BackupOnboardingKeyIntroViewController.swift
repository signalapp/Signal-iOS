//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BackupOnboardingKeyIntroViewController: OWSViewController, OWSNavigationChildController {
    private let onBackPressed: (BackupOnboardingKeyIntroViewController) -> Void
    private let onContinue: (BackupOnboardingKeyIntroViewController) -> Void

    init(
        onBackPressed: @escaping (BackupOnboardingKeyIntroViewController) -> Void,
        onContinue: @escaping (BackupOnboardingKeyIntroViewController) -> Void,
    ) {
        self.onBackPressed = onBackPressed
        self.onContinue = onContinue
        super.init()
        OWSTableViewController2.removeBackButtonText(viewController: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = .init(
            image: UIImage(named: "chevron-left-bold-28"),
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                onBackPressed(self)
            },
        )

        view.backgroundColor = .Signal.groupedBackground

        let logo = UIImageView(image: .backupsKey)
        logo.contentMode = .scaleAspectFit
        logo.isAccessibilityElement = false

        let titleLabel = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "BACKUP_ONBOARDING_KEY_INTRO_TITLE",
                comment: "Title for a view introducing the 'Recovery Key' during an onboarding flow.",
            ),
        )

        let bulletsStack = UIStackView.bulletPointsStack(content: [
            (
                image: UIImage(resource: .number),
                text: OWSLocalizedString(
                    "BACKUP_ONBOARDING_KEY_INTRO_BULLET_1",
                    comment: "Text for a bullet point in a view introducing the 'Recovery Key' during an onboarding flow.",
                ),
            ),
            (
                image: UIImage(resource: .lock),
                text: OWSLocalizedString(
                    "BACKUP_ONBOARDING_KEY_INTRO_BULLET_2",
                    comment: "Text for a bullet point in a view introducing the 'Recovery Key' during an onboarding flow.",
                ),
            ),
            (
                image: UIImage(resource: .errorCircle),
                text: OWSLocalizedString(
                    "BACKUP_ONBOARDING_KEY_INTRO_BULLET_3",
                    comment: "Text for a bullet point in a view introducing the 'Recovery Key' during an onboarding flow.",
                ),
            ),
        ])

        let continueButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "BACKUP_ONBOARDING_KEY_INTRO_CONTINUE_BUTTON_TITLE",
                comment: "Title for a continue button for a view introducing the 'Recovery Key' during an onboarding flow.",
            )),
            primaryAction: UIAction { [weak self] _ in self?.didTapContinue() },
        )

        let stackView = addStaticContentStackView(
            arrangedSubviews: [
                logo,
                titleLabel,
                bulletsStack,
                .vStretchingSpacer(),
                continueButton.enclosedInVerticalStackView(isFullWidthButton: true),
            ],
            isScrollable: true,
        )
        stackView.spacing = 24
        stackView.setCustomSpacing(36, after: titleLabel)
    }

    private func didTapContinue() {
        onContinue(self)
    }

    // MARK: - OWSNavigationChildController

    var shouldCancelNavigationBack: Bool {
        true
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    return UINavigationController(
        rootViewController: BackupOnboardingKeyIntroViewController(
            onBackPressed: { _ in },
            onContinue: { _ in },
        ),
    )
}

#endif

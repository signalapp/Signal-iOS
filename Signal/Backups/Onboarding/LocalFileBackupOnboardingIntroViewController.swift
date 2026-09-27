//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class LocalFileBackupOnboardingIntroViewController: OWSViewController {
    private let onContinue: (UIViewController) -> Void

    init(onContinue: @escaping (UIViewController) -> Void) {
        self.onContinue = onContinue
        super.init()
        OWSTableViewController2.removeBackButtonText(viewController: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.groupedBackground

        let logo = UIImageView(image: UIImage(named: "backups-on-device"))
        logo.contentMode = .scaleAspectFit
        logo.isAccessibilityElement = false

        let titleLabel = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "LOCAL_FILE_BACKUP_ONBOARDING_INTRO_TITLE",
                comment: "Title for a view introducing local file backups during the onboarding flow.",
            ),
        )

        let explanationLabel = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "LOCAL_FILE_BACKUP_ONBOARDING_INTRO_SUBTITLE",
                comment: "Subtitle for a view introducing local file backups during the onboarding flow.",
            ),
        )

        let bulletsStack = UIStackView.bulletPointsStack(content: [
            (
                image: UIImage(resource: .lock),
                text: OWSLocalizedString(
                    "LOCAL_FILE_BACKUP_ONBOARDING_INTRO_BULLET_1",
                    comment: "Bullet point on a view introducing local file backups during onboarding flow.",
                ),
            ),
            (
                image: UIImage(resource: .checkSquare),
                text: OWSLocalizedString(
                    "LOCAL_FILE_BACKUP_ONBOARDING_INTRO_BULLET_2",
                    comment: "Bullet point on a view introducing local file backups during onboarding flow.",
                ),
            ),
            (
                image: UIImage(resource: .trash),
                text: OWSLocalizedString(
                    "LOCAL_FILE_BACKUP_ONBOARDING_INTRO_BULLET_3",
                    comment: "Bullet point on a view introducing local file backups during onboarding flow.",
                ),
            ),
        ])

        let continueButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.continueButton),
            primaryAction: UIAction { [weak self] _ in self?.didTapContinue() },
        )

        let stackView = addStaticContentStackView(
            arrangedSubviews: [
                logo,
                titleLabel,
                explanationLabel,
                bulletsStack,
                .vStretchingSpacer(),
                continueButton.enclosedInVerticalStackView(isFullWidthButton: true),
            ],
            isScrollable: true,
        )
        stackView.spacing = 24
        stackView.setCustomSpacing(36, after: explanationLabel)
    }

    private func didTapContinue() {
        onContinue(self)
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    return UINavigationController(
        rootViewController: LocalFileBackupOnboardingIntroViewController { _ in },
    )
}

#endif

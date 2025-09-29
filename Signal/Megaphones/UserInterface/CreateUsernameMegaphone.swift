//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

final class CreateUsernameMegaphone: MegaphoneView {
    private let usernameSelectionCoordinator: UsernameSelectionCoordinator

    init(
        usernameSelectionCoordinator: UsernameSelectionCoordinator,
        experienceUpgrade: ExperienceUpgrade,
        fromViewController: UIViewController
    ) {
        self.usernameSelectionCoordinator = usernameSelectionCoordinator

        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString(
            "CREATE_USERNAME_MEGAPHONE_TITLE",
            comment: "Title for an interactive in-app prompt to set up a Signal username."
        )

        bodyText = OWSLocalizedString(
            "CREATE_USERNAME_MEGAPHONE_BODY",
            comment: "Body text for an interactive in-app prompt to set up a Signal username."
        )

        imageName = "usernames-48-color"
        imageContentMode = .center

        let setUpButton = Button(title: CommonStrings.learnMore) { [weak self, weak fromViewController] in
            guard
                let self,
                let fromViewController
            else { return }

            self.onSetUpTapped(fromViewController: fromViewController)
        }

        let notNowButton = Button(title: CommonStrings.notNowButton) { [weak self] in
            guard let self else { return }
            self.onNotNowTapped()
        }

        setButtons(primary: setUpButton, secondary: notNowButton)
    }

    @available(*, unavailable, message: "Use other constructor!")
    required init(coder: NSCoder) {
        owsFail("Use other constructor!")
    }

    private func onSetUpTapped(fromViewController: UIViewController) {
        markAsSnoozedWithSneakyTransaction()

        dismiss(animated: true) {
            self.usernameSelectionCoordinator.present(fromViewController: fromViewController)
        }
    }

    private func onNotNowTapped() {
        markAsSnoozedWithSneakyTransaction()

        dismiss(animated: true)
    }
}

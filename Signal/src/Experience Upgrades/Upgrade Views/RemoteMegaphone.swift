//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class RemoteMegaphone: MegaphoneView {
    private let megaphoneModel: RemoteMegaphoneModel

    init(
        experienceUpgrade: ExperienceUpgrade,
        remoteMegaphoneModel: RemoteMegaphoneModel,
        fromViewController: UIViewController
    ) {
        megaphoneModel = remoteMegaphoneModel

        super.init(experienceUpgrade: experienceUpgrade)

        titleText = megaphoneModel.translation.title
        bodyText = megaphoneModel.translation.body

        if let imageLocalUrl = megaphoneModel.translation.imageLocalUrl {
            if let image = UIImage(contentsOfFile: imageLocalUrl.path) {
                self.image = image
            } else {
                owsFailDebug("Expected local image, but image was not loaded!")
            }
        }

        if let primary = megaphoneModel.presentablePrimaryAction {
            let primaryButton = MegaphoneView.Button(title: primary.presentableText) { [weak self, weak fromViewController] in
                guard
                    let self = self,
                    let fromViewController = fromViewController
                else { return }

                self.performAction(
                    primary.action,
                    fromViewController: fromViewController,
                    buttonDescriptor: "primary"
                )
            }

            if let secondary = megaphoneModel.presentableSecondaryAction {
                let secondaryButton = MegaphoneView.Button(title: secondary.presentableText) { [weak self, weak fromViewController] in
                    guard
                        let self = self,
                        let fromViewController = fromViewController
                    else { return }

                    self.performAction(
                        secondary.action,
                        fromViewController: fromViewController,
                        buttonDescriptor: "secondary"
                    )
                }

                setButtons(primary: primaryButton, secondary: secondaryButton)
            } else {
                setButtons(primary: primaryButton)
            }
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Perform actions

    /// Perform the given action.
    private func performAction(
        _ action: RemoteMegaphoneModel.Manifest.Action,
        fromViewController: UIViewController,
        buttonDescriptor: String
    ) {
        switch action {
        case .snooze:
            markAsSnoozedWithSneakyTransaction()
            dismiss()
        case .finish:
            markAsCompleteWithSneakyTransaction()
            dismiss()
        case .donate:
            let navController = OWSNavigationController(rootViewController: DonationSettingsViewController())
            fromViewController.present(navController, animated: true) { [weak self] in
                guard let self = self else { return }

                // Snooze regardless of outcome from donation screen.
                self.markAsSnoozedWithSneakyTransaction()
                self.dismiss(animated: false)
            }
        case .unrecognized(let actionId):
            owsFailDebug("Unrecognized action with ID \(actionId) should never have made it into \(buttonDescriptor) button!")
            dismiss()
        }
    }
}

// MARK: - Presentable actions

private extension RemoteMegaphoneModel {
    struct PresentableAction {
        let action: Manifest.Action
        let presentableText: String

        fileprivate init?(
            action: Manifest.Action?,
            presentableText: String?
        ) {
            guard
                let action = action,
                let presentableText = presentableText
            else {
                return nil
            }

            self.action = action
            self.presentableText = presentableText
        }
    }

    var presentablePrimaryAction: PresentableAction? {
        PresentableAction(
            action: manifest.primaryAction,
            presentableText: translation.primaryActionText
        )
    }

    var presentableSecondaryAction: PresentableAction? {
        PresentableAction(
            action: manifest.secondaryAction,
            presentableText: translation.secondaryActionText
        )
    }
}

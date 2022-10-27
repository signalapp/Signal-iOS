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
        fromViewController _: UIViewController
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
            let primaryButton = MegaphoneView.Button(title: primary.presentableText) { [weak self] in
                switch primary.action {
                case .unrecognized(let actionId):
                    owsFailDebug("Unrecognized primary action with ID \(actionId) should never have made it into a button!")
                }

                self?.dismiss()
            }

            if let secondary = megaphoneModel.presentableSecondaryAction {
                let secondaryButton = MegaphoneView.Button(title: secondary.presentableText) { [weak self] in
                    switch secondary.action {
                    case .unrecognized(let actionId):
                        owsFailDebug("Unrecognized secondary action with ID \(actionId) should never have made it into a button!")
                    }

                    self?.dismiss()
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
}

extension RemoteMegaphoneModel {
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

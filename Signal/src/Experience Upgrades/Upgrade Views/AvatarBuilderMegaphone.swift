//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

class AvatarBuilderMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = NSLocalizedString("AVATAR_BUILDER_MEGAPHONE_TITLE", comment: "Title for avatar builder megaphone")
        bodyText = NSLocalizedString("AVATAR_BUILDER_MEGAPHONE_BODY", comment: "Body for avatar builder megaphone")
        imageName = "avatar_megaphone"

        setButtons(
            primary: Button(title: NSLocalizedString(
                "AVATAR_BUILDER_MEGAPHONE_ACTION",
                comment: "Action text for avatar builder megaphone"
            )) { [weak self] in
                guard let self = self else { return }
                self.dismiss {
                    self.markAsComplete()
                    Self.signalApp.showAppSettings(mode: .avatarBuilder)
                }
            },
            secondary: Button(title: CommonStrings.notNowButton) { [weak self] in
                self?.markAsComplete()
                self?.dismiss()
            }
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tappedDismiss() {
        dismiss { self.markAsComplete() }
    }
}

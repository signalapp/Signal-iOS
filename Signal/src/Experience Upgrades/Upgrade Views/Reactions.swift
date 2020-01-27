//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class ReactionsMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = NSLocalizedString("REACTION_MEGAPHONE_TITLE", comment: "Title for the megaphone introducing reactions")
        bodyText = NSLocalizedString("REACTION_MEGAPHONE_BODY", comment: "Body for the megaphone introducing reactions")

        imageSize = .large
        animation = Animation(
            name: "reactionsMegaphone",
            backgroundImageName: "reactions-megaphone-bg",
            backgroundImageInset: 12,
            loopMode: .repeat(3),
            backgroundBehavior: .forceFinish,
            contentMode: .center
        )
    }

    override func tappedDismiss() {
        dismiss { self.markAsComplete() }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

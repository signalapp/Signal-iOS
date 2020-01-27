//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class ReactionsMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = "Introducing Reactions"
        bodyText = "Now you can 👍 a message with a touch. Tap and hold a message to get started."

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

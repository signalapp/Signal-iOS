//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

class ChatColorsMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = NSLocalizedString("CHAT_COLORS_MEGAPHONE_TITLE", comment: "Title for char colors megaphone")
        bodyText = NSLocalizedString("CHAT_COLORS_MEGAPHONE_BODY", comment: "Body for char colors megaphone")
        self.animation = Animation(name: "color-bubble-64")
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tappedDismiss() {
        dismiss { self.markAsComplete() }
    }
}

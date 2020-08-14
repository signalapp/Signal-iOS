//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class MentionsMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = NSLocalizedString("MENTIONS_MEGAPHONE_TITLE", comment: "Title for mentions megaphone")
        bodyText = NSLocalizedString("MENTIONS_MEGAPHONE_BODY", comment: "Body for mentions megaphone")
        imageName = "mentionsMegaphone"
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tappedDismiss() {
         dismiss { self.markAsComplete() }
     }
}

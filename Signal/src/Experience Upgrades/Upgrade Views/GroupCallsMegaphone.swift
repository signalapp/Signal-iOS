//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class GroupCallsMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)
        imageName = "Group-Calls-Megaphone"

        titleText = NSLocalizedString("GROUP_CALLS_MEGAPHONE_TITLE",
                                      comment: "Title for group calls megaphone")
        bodyText = NSLocalizedString("GROUP_CALLS_MEGAPHONE_BODY",
                                     comment: "Body for group calls megaphone")
    }

    override func tappedDismiss() {
        dismiss { self.markAsComplete() }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

class ChatColorsMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = NSLocalizedString("CHAT_COLORS_MEGAPHONE_TITLE", comment: "Title for chat colors megaphone")
        bodyText = NSLocalizedString("CHAT_COLORS_MEGAPHONE_BODY", comment: "Body for chat colors megaphone")
        self.animation = Animation(name: "color-bubble-64")

        setButtons(
            primary: Button(title: NSLocalizedString(
                "CHAT_COLORS_MEGAPHONE_ACTION",
                comment: "Action text for char colors megaphone"
            )) { [weak self] in
                guard let self = self else { return }
                self.dismiss {
                    self.markAsComplete()
                    Self.signalApp.showAppSettings(mode: .appearance)
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

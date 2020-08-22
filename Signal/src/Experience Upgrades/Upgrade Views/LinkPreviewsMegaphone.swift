//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class LinkPreviewsMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)
        imageName = "linkPreviewsMegaphone"

        titleText = NSLocalizedString("LINKPREVIEWS_MEGAPHONE_TITLE",
                                      comment: "Title for link previews megaphone")
        bodyText = NSLocalizedString("LINKPREVIEWS_MEGAPHONE_BODY",
                                     comment: "Body for link previews megaphone")
        let okayButtonText = NSLocalizedString("BUTTON_OKAY",
                                               comment: "Label for the 'okay' button.")
        let disableButtonText = NSLocalizedString("LINKPREVIEWS_MEGAPHONE_BUTTON_DISABLE",
                                                  comment: "Disable button for link previews megaphone")

        setButtons(
            primary: Button(title: okayButtonText) { [weak self] in
                self?.dismissAndSetLinkPreviews(enabled: true)
            },
            secondary: Button(title: disableButtonText) { [weak self] in
                self?.dismissAndSetLinkPreviews(enabled: false)
            }
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func dismissAndSetLinkPreviews(enabled: Bool) {
        SDSDatabaseStorage.shared.write { tx in
            SSKPreferences.setAreLinkPreviewsEnabled(enabled, sendSyncMessage: true, transaction: tx)
            self.markAsComplete(transaction: tx)
        }
        dismiss()
    }
}

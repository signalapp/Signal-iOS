//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

class SharingSuggestionsMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)
        imageName = "megaphone-sharing-suggestions"

        titleText = NSLocalizedString("SHARING_SUGGESTIONS_MEGAPHONE_TITLE",
                                      comment: "Title for sharing suggestions megaphone")
        bodyText = NSLocalizedString("SHARING_SUGGESTIONS_MEGAPHONE_BODY",
                                     comment: "Body for sharing suggestions megaphone")
        let enableButtonText = NSLocalizedString("SHARING_SUGGESTIOONS_MEGAPHONE_BUTTON_ENABLE",
                                               comment: "Enable button for sharing suggestions megaphone")
        let disableButtonText = NSLocalizedString("SHARING_SUGGESTIOONS_MEGAPHONE_BUTTON_DISABLE",
                                                  comment: "Disable button for sharing suggestions megaphone")

        setButtons(
            primary: Button(title: enableButtonText) { [weak self] in
                self?.dismissAndSetSharingSuggestions(enabled: true)
            },
            secondary: Button(title: disableButtonText) { [weak self] in
                self?.dismissAndSetSharingSuggestions(enabled: false)
            }
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func dismissAndSetSharingSuggestions(enabled: Bool) {
        SDSDatabaseStorage.shared.write { tx in
            SSKPreferences.setAreSharingSuggestionsEnabled(enabled, transaction: tx)
            self.markAsComplete(transaction: tx)
        }
        dismiss()
    }
}

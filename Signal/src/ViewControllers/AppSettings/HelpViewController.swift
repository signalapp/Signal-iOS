//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSHelpViewController)
final class HelpViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        contents = constructContents()
    }

    private func constructContents() -> OWSTableContents {
        let helpTitle = NSLocalizedString("SETTINGS_HELP",
                                          comment: "Title for support page in app settings.")
        let supportCenterLabel = NSLocalizedString("HELP_SUPPORT_CENTER",
                                                   comment: "Help item that takes the user to the Signal support website")
        let contactLabel = NSLocalizedString("HELP_CONTACT_US",
                                             comment: "Help item allowing the user to file a support request")
        let localizedSheetTitle = NSLocalizedString("EMAIL_SIGNAL_TITLE",
                                                    comment: "Title for the fallback support sheet if user cannot send email")
        let localizedSheetMessage = NSLocalizedString("EMAIL_SIGNAL_MESSAGE",
                                                      comment: "Description for the fallback support sheet if user cannot send email")

        let contents = OWSTableContents()
        contents.title = helpTitle

        let firstSection = OWSTableSection()
        firstSection.add(.disclosureItem(
            withText: supportCenterLabel,
            actionBlock: {
                UIApplication.shared.open(SupportConstants.supportURL, options: [:])
            }
        ))
        firstSection.add(.disclosureItem(
            withText: contactLabel,
            actionBlock: {
                guard ComposeSupportEmailOperation.canSendEmails else {
                    let fallbackSheet = ActionSheetController(title: localizedSheetTitle,
                                                              message: localizedSheetMessage)
                    let buttonTitle = NSLocalizedString("BUTTON_OKAY", comment: "Label for the 'okay' button.")
                    fallbackSheet.addAction(ActionSheetAction(title: buttonTitle, style: .default))
                    self.presentActionSheet(fallbackSheet)
                    return
                }
                let supportVC = ContactSupportViewController()
                let navVC = OWSNavigationController(rootViewController: supportVC)
                self.presentFormSheet(navVC, animated: true)
            }
        ))
        contents.addSection(firstSection)

        return contents
    }
}

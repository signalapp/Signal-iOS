//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSHelpViewController)
final class HelpViewController: OWSTableViewController {

    override func viewDidLoad() {
        contents = constructContents()
    }

    fileprivate func constructContents() -> OWSTableContents {
        let helpTitle = NSLocalizedString("SETTINGS_HELP",
                                          comment: "Title for support page in app settings.")
        let supportCenterLabel = NSLocalizedString("HELP_SUPPORT_CENTER",
                                                   comment: "Help item that takes the user to the Signal support website")
        let contactLabel = NSLocalizedString("HELP_CONTACT_US",
                                             comment: "Help item allowing the user to file a support request")

        return OWSTableContents(title: helpTitle, sections: [
            OWSTableSection(header: {
                // TODO: Replace this temporary view with design asset
                guard let signalAsset = UIImage(named: "signal-logo-128") else { return nil }

                let header = UIView()
                header.backgroundColor = Theme.launchScreenBackground
                let signalLogo = UIImageView(image: signalAsset)
                signalLogo.contentMode = .scaleAspectFit

                header.addSubview(signalLogo)
                signalLogo.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30))
                return header

            }, items: [
                OWSTableItem.disclosureItem(withText: supportCenterLabel, actionBlock: {
                    UIApplication.shared.open(SupportConstants.supportURL, options: [:])
                }),

                OWSTableItem.disclosureItem(withText: contactLabel, actionBlock: {
                    guard ComposeSupportEmailOperation.canSendEmails else {
                        let localizedSheetTitle = NSLocalizedString("EMAIL_SIGNAL_TITLE",
                                                                    comment: "Title for the fallback support sheet if user cannot send email")
                        let localizedSheetMessage = NSLocalizedString("EMAIL_SIGNAL_MESSAGE",
                                                                      comment: "Description for the fallback support sheet if user cannot send email")
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
                })
            ])
        ])
    }
}

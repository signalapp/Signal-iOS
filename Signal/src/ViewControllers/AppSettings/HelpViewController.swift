//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSHelpViewController)
class HelpViewController: OWSTableViewController {
    private lazy var declaredContentDefinition = constructContents()
    override var contents: OWSTableContents {
        get {
            return declaredContentDefinition
        }
        set {
            // LSP violation
            owsFailDebug("Help contents are immutable")
        }
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
                guard let signalAsset = UIImage(named: "signal-logo-128") else { return nil }

                let header = UIView()
                header.backgroundColor = Theme.launchScreenBackground
                let signalLogo = UIImageView(image: signalAsset)
                signalLogo.contentMode = .scaleAspectFit

                header.addSubview(signalLogo)
                signalLogo.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30))
                return header

            }, items: [
                OWSTableItem(title: supportCenterLabel, actionBlock: {
                    guard let supportURL = URL(string: TSConstants.signalSupportURL) else {
                        owsFailDebug("Invalid URL")
                        return
                    }
                    UIApplication.shared.open(supportURL, options: [:])
                }),

                OWSTableItem(title: contactLabel, actionBlock: {
                    let supportVC = ContactSupportViewController()
                    let navVC = OWSNavigationController(rootViewController: supportVC)
                    self.presentFormSheet(navVC, animated: true)
                })
            ])
        ])
    }
}

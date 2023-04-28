//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalMessaging

@objc(OWSHelpViewController)
final class HelpViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()
    }

    private func updateTableContents() {
        let helpTitle = CommonStrings.help
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

        let helpSection = OWSTableSection()
        helpSection.add(.disclosureItem(
            withText: supportCenterLabel,
            actionBlock: { [weak self] in
                let vc = SFSafariViewController(url: SupportConstants.supportURL)
                self?.present(vc, animated: true, completion: nil)
            }
        ))
        helpSection.add(.disclosureItem(
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
        contents.addSection(helpSection)

        let loggingSection = OWSTableSection()
        loggingSection.headerTitle = NSLocalizedString("LOGGING_SECTION", comment: "Title for the 'logging' help section.")
        loggingSection.footerTitle = NSLocalizedString("LOGGING_SECTION_FOOTER", comment: "Footer for the 'logging' help section.")
        loggingSection.add(.switch(
            withText: NSLocalizedString("SETTINGS_ADVANCED_DEBUGLOG", comment: ""),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "enable_debug_log"),
            isOn: { OWSPreferences.isLoggingEnabled() },
            isEnabledBlock: { true },
            target: self,
            selector: #selector(didToggleEnableLogSwitch)
        ))
        if OWSPreferences.isLoggingEnabled() {
            loggingSection.add(.actionItem(
                name: NSLocalizedString("SETTINGS_ADVANCED_SUBMIT_DEBUGLOG", comment: ""),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "submit_debug_log"),
                actionBlock: {
                    Logger.info("Submitting debug logs")
                    Logger.flush()
                    DebugLogs.submitLogs()
                }
            ))
        }
        contents.addSection(loggingSection)

        let aboutSection = OWSTableSection()
        aboutSection.headerTitle = NSLocalizedString("ABOUT_SECTION_TITLE", comment: "Title for the 'about' help section")
        aboutSection.footerTitle = NSLocalizedString(
            "SETTINGS_COPYRIGHT",
            comment: "Footer for the 'about' help section"
        )
        aboutSection.add(.copyableItem(label: NSLocalizedString("SETTINGS_VERSION", comment: ""),
                                       value: AppVersion.shared.currentAppVersion4))
        aboutSection.add(.disclosureItem(
            withText: NSLocalizedString("SETTINGS_LEGAL_TERMS_CELL", comment: ""),
            actionBlock: { [weak self] in
                let url = TSConstants.legalTermsUrl
                let vc = SFSafariViewController(url: url)
                self?.present(vc, animated: true, completion: nil)
            }
        ))
        contents.addSection(aboutSection)

        self.contents = contents
    }

    @objc
    func didToggleEnableLogSwitch(sender: UISwitch) {
        if sender.isOn {
            Logger.info("disabling logging.")
            DebugLogger.shared().wipeLogs()
            DebugLogger.shared().disableFileLogging()
        } else {
            DebugLogger.shared().enableFileLogging()
            Logger.info("enabling logging.")
        }

        OWSPreferences.setIsLoggingEnabled(sender.isOn)

        updateTableContents()
    }
}

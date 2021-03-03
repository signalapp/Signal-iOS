//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class AppSettingsViewController: OWSTableViewController2 {

    @objc
    class func inModalNavigationController() -> OWSNavigationController {
        return OWSNavigationController(rootViewController: AppSettingsViewController())
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_NAV_BAR_TITLE", comment: "Title for settings activity")
        navigationItem.rightBarButtonItem = .init(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        updateTableContents()
    }

    @objc
    func didTapDone() {
        dismiss(animated: true)
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let section1 = OWSTableSection()
        section1.add(.disclosureItem(
            icon: .settingsAccount,
            name: NSLocalizedString("SETTINGS_ACCOUNT", comment: "Title for the 'account' link in settings."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "account"),
            actionBlock: {
                // TODO:
            }
        ))
        section1.add(.disclosureItem(
            icon: .settingsLinkedDevices,
            name: NSLocalizedString("LINKED_DEVICES_TITLE", comment: "Menu item and navbar title for the device manager"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "linked-devices"),
            actionBlock: { [weak self] in
                let vc = LinkedDevicesTableViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        contents.addSection(section1)

        let section2 = OWSTableSection()
        section2.add(.disclosureItem(
            icon: .settingsAppearance,
            name: NSLocalizedString("SETTINGS_APPEARANCE_TITLE", comment: "The title for the appearance settings."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "appearance"),
            actionBlock: { [weak self] in
                let vc = AppearanceSettingsTableViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        section2.add(.disclosureItem(
            icon: .settingsChats,
            name: NSLocalizedString("SETTINGS_CHATS", comment: "Title for the 'chats' link in settings."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "chats"),
            actionBlock: {
                // TODO:
            }
        ))
        section2.add(.disclosureItem(
            icon: .settingsNotifications,
            name: NSLocalizedString("SETTINGS_NOTIFICATIONS", comment: "The title for the notification settings."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "notifications"),
            actionBlock: { [weak self] in
                let vc = NotificationSettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        section2.add(.disclosureItem(
            icon: .settingsPrivacy,
            name: NSLocalizedString("SETTINGS_PRIVACY_TITLE", comment: "The title for the privacy settings."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "privacy"),
            actionBlock: { [weak self] in
                let vc = PrivacySettingsTableViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        section2.add(.disclosureItem(
            icon: .settingsDataUsage,
            name: NSLocalizedString("SETTINGS_DATA", comment: "Label for the 'data' section of the app settings."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "data-usage"),
            actionBlock: { [weak self] in
                let vc = DataSettingsTableViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        contents.addSection(section2)

        let section3 = OWSTableSection()
        section3.add(.disclosureItem(
            icon: .settingsHelp,
            name: NSLocalizedString("SETTINGS_HELP", comment: "Title for support page in app settings."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "help"),
            actionBlock: { [weak self] in
                let vc = HelpViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        contents.addSection(section3)

        let section4 = OWSTableSection()
        section4.add(.disclosureItem(
            icon: .settingsInvite,
            name: NSLocalizedString("SETTINGS_INVITE_TITLE", comment: "Settings table view cell label"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "invite"),
            actionBlock: { [weak self] in
                self?.showInviteFlow()
            }
        ))
        section4.add(.item(
            icon: .settingsDonate,
            name: NSLocalizedString("SETTINGS_DONATE", comment: "Title for the 'donate to signal' link in settings."),
            accessoryImage: #imageLiteral(resourceName: "open-externally-14"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "donate"),
            actionBlock: {
                UIApplication.shared.open(URL(string: "https://signal.org/donate")!, options: [:], completionHandler: nil)
            }
        ))
        contents.addSection(section4)

        #if DEBUG
        if DebugUITableViewController.useDebugUI() {
            let debugSection = OWSTableSection()
            debugSection.add(.disclosureItem(
                withText: "Debug UI",
                actionBlock: { [weak self] in
                    guard let self = self else { return }
                    DebugUITableViewController.presentDebugUI(from: self)
                }
            ))
            contents.addSection(debugSection)
        }
        #endif

        self.contents = contents
    }

    private var inviteFlow: InviteFlow?
    private func showInviteFlow() {
        let inviteFlow = InviteFlow(presentingViewController: self)
        self.inviteFlow = inviteFlow
        inviteFlow.present(isAnimated: true, completion: nil)
    }
}

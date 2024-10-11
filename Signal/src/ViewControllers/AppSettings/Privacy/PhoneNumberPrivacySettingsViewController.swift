//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PhoneNumberPrivacySettingsViewController: OWSTableViewController2 {

    private var phoneNumberDiscoverability: PhoneNumberDiscoverability!
    private var phoneNumberSharingMode: PhoneNumberSharingMode!

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        loadValues()
        title = OWSLocalizedString(
            "SETTINGS_PHONE_NUMBER_PRIVACY_TITLE",
            comment: "The title for phone number privacy settings.")
        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateTableContents()
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    private func loadValues() {
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            phoneNumberDiscoverability = tsAccountManager.phoneNumberDiscoverability(tx: tx.asV2Read).orDefault
            phoneNumberSharingMode = SSKEnvironment.shared.udManagerRef.phoneNumberSharingMode(tx: tx.asV2Read).orDefault
        }
    }

    // MARK: Build Table

    private func updateTableContents() {
        let contents = OWSTableContents()
        var sections = [OWSTableSection]()

        let seeMyNumberSection = OWSTableSection()
        seeMyNumberSection.headerTitle = OWSLocalizedString(
            "SETTINGS_PHONE_NUMBER_SHARING_TITLE",
            comment: "The title for the phone number sharing setting section."
        )
        seeMyNumberSection.customFooterView = createSharingFooter()
        seeMyNumberSection.add(sharingItem(.everybody))
        seeMyNumberSection.add(sharingItem(.nobody))
        sections.append(seeMyNumberSection)

        let findByNumberSection = OWSTableSection()
        findByNumberSection.headerTitle = OWSLocalizedString(
            "SETTINGS_PHONE_NUMBER_DISCOVERABILITY_TITLE",
            comment: "The title for the phone number discoverability setting section."
        )
        findByNumberSection.footerTitle = phoneNumberDiscoverability.descriptionForDiscoverability
        findByNumberSection.add(everybodyDiscoverabilityItem())
        findByNumberSection.add(nobodyDiscoverabilityItem(sharingMode: phoneNumberSharingMode))

        sections.append(findByNumberSection)

        contents.add(sections: sections)
        self.contents = contents
    }

    // MARK: Update Setting Values

    private func everybodyDiscoverabilityItem() -> OWSTableItem {
        return OWSTableItem(
            text: PhoneNumberDiscoverability.everybody.nameForDiscoverability,
            actionBlock: { [weak self] in
                self?.updateDiscoverability(.everybody)
            },
            accessoryType: self.phoneNumberDiscoverability == .everybody ? .checkmark : .none
        )
    }

    private func nobodyDiscoverabilityItem(sharingMode: PhoneNumberSharingMode) -> OWSTableItem {
        let textColor: UIColor = {
            switch sharingMode {
            case .everybody:
                return Theme.secondaryTextAndIconColor
            case .nobody:
                return Theme.primaryTextColor
            }
        }()

        let accessory: UITableViewCell.AccessoryType = {
            switch (sharingMode, self.phoneNumberDiscoverability) {
            case (.everybody, _), (.nobody, .everybody), (.nobody, .none):
                return .none
            case (.nobody, .nobody):
                return .checkmark
            }
        }()

        return OWSTableItem(
            text: PhoneNumberDiscoverability.nobody.nameForDiscoverability,
            textColor: textColor,
            actionBlock: { [weak self] in
                switch sharingMode {
                case .everybody:
                    self?.presentPhoneNumberDiscoverabilityDisabledToast()
                case .nobody:
                    self?.promptToDisableDiscoverability()
                }
            },
            accessoryType: accessory
        )
    }

    private func sharingItem(_ mode: PhoneNumberSharingMode) -> OWSTableItem {
        return OWSTableItem(
            text: Self.nameForMode(mode),
            actionBlock: { [weak self] in
                self?.updatePhoneNumberSharing(mode)
            },
            accessoryType: phoneNumberSharingMode == mode ? .checkmark : .none
        )
    }

    // MARK: Alerts

    private func presentPhoneNumberDiscoverabilityDisabledToast() {
        presentToast(text: OWSLocalizedString(
            "SETTINGS_PHONE_NUMBER_DISCOVERABILITY_DISABLED_TOAST",
            comment: "A toast that displays when the user attempts to set discoverability to 'nobody' when their phone number sharing is set to 'everybody', which is not allowed."
        ))
    }

    private func promptToDisableDiscoverability() {
        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString(
                "SETTINGS_PHONE_NUMBER_DISCOVERABILITY_NOBODY_CONFIRMATION_TITLE",
                comment: "The title for a sheet asking for confirmation that the user wants to set their phone number discoverability to 'nobody'."
            ),
            message: OWSLocalizedString(
                "SETTINGS_PHONE_NUMBER_DISCOVERABILITY_NOBODY_CONFIRMATION_DESCRIPTION",
                comment: "The description for a sheet asking for confirmation that the user wants to set their phone number discoverability to 'nobody'."
            )
        ) { [weak self] _ in
            self?.updateDiscoverability(.nobody)
        }
    }

    // MARK: Update Table UI

    private func updateDiscoverability(_ phoneNumberDiscoverability: PhoneNumberDiscoverability) {
        guard self.phoneNumberDiscoverability != phoneNumberDiscoverability else { return }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite(block: { transaction in
            DependenciesBridge.shared.phoneNumberDiscoverabilityManager.setPhoneNumberDiscoverability(
                phoneNumberDiscoverability,
                updateAccountAttributes: true,
                updateStorageService: true,
                authedAccount: .implicit(),
                tx: transaction.asV2Write
            )
        }) { [weak self] in
            guard let self else { return }
            self.loadValues()
            self.updateTableContents()
        }
    }

    private func updatePhoneNumberSharing(_ mode: PhoneNumberSharingMode) {
        guard phoneNumberSharingMode != mode else { return }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite(block: { transaction in
            SSKEnvironment.shared.udManagerRef.setPhoneNumberSharingMode(mode, updateStorageServiceAndProfile: true, tx: transaction)

            // If sharing is set to `everybody`, discovery needs to be
            // updated to match this.
            if mode == .everybody {
                DependenciesBridge.shared.phoneNumberDiscoverabilityManager.setPhoneNumberDiscoverability(
                    .everybody,
                    updateAccountAttributes: true,
                    updateStorageService: true,
                    authedAccount: .implicit(),
                    tx: transaction.asV2Write
                )
            }
        }) { [weak self] in
            guard let self else { return }
            self.loadValues()
            self.updateTableContents()
        }
    }

    // MARK: Phone number sharing footer

    /// Creates a footer view for the phone number sharing section.
    ///
    /// The height of this view will remain constant when
    /// `phoneNumberSharingMode` and `phoneNumberDiscoverability` change as its
    /// height is calculated based on the text of each possible description.
    private func createSharingFooter() -> UIView {
        let sharingDescriptionEverybody = sharingDescriptionEverybody()
        let sharingDescriptionNobodyDiscoverabilityNobody = sharingDescriptionNobodyDiscoverabilityNobody()
        let sharingDescriptionNobodyDiscoverabilityEverybody = sharingDescriptionNobodyDiscoverabilityEverybody()

        // Determine which footer text to show.
        switch (phoneNumberSharingMode!, phoneNumberDiscoverability!) {
        case (.everybody, _):
            sharingDescriptionEverybody.isHidden = false
            sharingDescriptionNobodyDiscoverabilityNobody.isHidden = true
            sharingDescriptionNobodyDiscoverabilityEverybody.isHidden = true
        case (.nobody, .everybody):
            sharingDescriptionEverybody.isHidden = true
            sharingDescriptionNobodyDiscoverabilityNobody.isHidden = true
            sharingDescriptionNobodyDiscoverabilityEverybody.isHidden = false
        case (.nobody, .nobody):
            sharingDescriptionEverybody.isHidden = true
            sharingDescriptionNobodyDiscoverabilityNobody.isHidden = false
            sharingDescriptionNobodyDiscoverabilityEverybody.isHidden = true
        }

        // Add all of the possible footer descriptions so that the height
        // doesn't change when the selected setting changes.
        let container = UIView.container()
        [
            sharingDescriptionEverybody,
            sharingDescriptionNobodyDiscoverabilityNobody,
            sharingDescriptionNobodyDiscoverabilityEverybody,
        ].forEach { textView in
            container.addSubview(textView)
            textView.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)
            textView.autoPinEdge(toSuperviewEdge: .bottom, relation: .greaterThanOrEqual)
        }
        return container
    }

    private func sharingDescriptionEverybody() -> UITextView {
        let textView = buildFooterTextView(withDeepInsets: true)
        textView.text = OWSLocalizedString(
            "PHONE_NUMBER_SHARING_EVERYBODY_DESCRIPTION",
            comment: "A user friendly description of the 'everybody' phone number sharing mode."
        )
        return textView
    }

    private func sharingDescriptionNobodyDiscoverabilityNobody() -> UITextView {
        let textView = buildFooterTextView(withDeepInsets: true)
        textView.text = OWSLocalizedString(
            "PHONE_NUMBER_SHARING_NOBODY_DESCRIPTION_DISCOVERABILITY_NOBODY",
            comment: "A user-friendly description of the 'nobody' phone number sharing mode when phone number discovery is set to 'nobody'."
        )
        return textView
    }

    private func sharingDescriptionNobodyDiscoverabilityEverybody() -> UITextView {
        let textView = buildFooterTextView(withDeepInsets: true)
        textView.text = OWSLocalizedString(
            "PHONE_NUMBER_SHARING_NOBODY_DESCRIPTION_DISCOVERABILITY_EVERYBODY",
            comment: "A user-friendly description of the 'nobody' phone number sharing mode when phone number discovery is set to 'everybody'."
        )
        return textView
    }
}

// MARK: - PhoneNumberDiscoverability + strings

extension PhoneNumberDiscoverability {
    var nameForDiscoverability: String {
        switch self {
        case .everybody:
            return OWSLocalizedString(
                "PHONE_NUMBER_DISCOVERABILITY_EVERYBODY",
                comment: "A user friendly name for the 'everybody' phone number discoverability mode.")
        case .nobody:
            return OWSLocalizedString(
                "PHONE_NUMBER_DISCOVERABILITY_NOBODY",
                comment: "A user friendly name for the 'nobody' phone number discoverability mode.")
        }
    }

    var descriptionForDiscoverability: String {
        switch self {
        case .everybody:
            return OWSLocalizedString(
                "PHONE_NUMBER_DISCOVERABILITY_EVERYBODY_DESCRIPTION",
                comment: "A user friendly description of the 'everybody' phone number discoverability mode.")
        case .nobody:
            return OWSLocalizedString(
                "PHONE_NUMBER_DISCOVERABILITY_NOBODY_DESCRIPTION",
                comment: "A user friendly description of the 'nobody' phone number discoverability mode.")
        }
    }
}

// MARK: - Phone number sharing strings

extension PhoneNumberPrivacySettingsViewController {
    fileprivate class func nameForMode(_ mode: PhoneNumberSharingMode) -> String {
        switch mode {
        case .everybody:
            return OWSLocalizedString(
                "PHONE_NUMBER_SHARING_EVERYBODY",
                comment: "A user friendly name for the 'everybody' phone number sharing mode.")
        case .nobody:
            return OWSLocalizedString(
                "PHONE_NUMBER_SHARING_NOBODY",
                comment: "A user friendly name for the 'nobody' phone number sharing mode.")
        }
    }
}

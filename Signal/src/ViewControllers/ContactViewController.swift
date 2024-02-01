//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import MessageUI
import SignalMessaging
import SignalServiceKit
import SignalUI

class ContactViewController: OWSTableViewController2 {

    private enum ContactViewMode {
        case systemContactWithSignal
        case systemContactWithoutSignal
        case nonSystemContact
        case noPhoneNumber
    }

    private var viewMode: ContactViewMode {
        didSet {
            AssertIsOnMainThread()

            if oldValue != viewMode && isViewLoaded {
                updateContent()
            }
        }
    }

    private let contactShare: ContactShareViewModel
    private var sendablePhoneNumbers: [String]

    private lazy var contactShareViewHelper: ContactShareViewHelper = {
        let helper = ContactShareViewHelper()
        helper.delegate = self
        return helper
    }()

    // MARK: View Controller

    required init(contactShare: ContactShareViewModel) {
        self.contactShare = contactShare
        let phoneNumberPartition = Self.phoneNumberPartition(for: contactShare)
        self.viewMode = Self.viewMode(for: phoneNumberPartition)
        self.sendablePhoneNumbers = phoneNumberPartition.sendablePhoneNumbers

        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateMode),
                                               name: .OWSContactsManagerSignalAccountsDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateMode),
                                               name: SSKReachability.owsReachabilityDidChange,
                                               object: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        updateContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        contactsManagerImpl.requestSystemContactsOnce { [weak self] _ in
            self?.updateMode()
        }
    }

    // MARK: Contact Data

    private static func phoneNumberPartition(for contactShare: ContactShareViewModel) -> OWSContact.PhoneNumberPartition {
        return databaseStorage.read(block: contactShare.dbRecord.phoneNumberPartition(tx:))
    }

    private static func viewMode(for phoneNumberPartition: OWSContact.PhoneNumberPartition) -> ContactViewMode {
        return phoneNumberPartition.map(
            ifSendablePhoneNumbers: { _ in .systemContactWithSignal },
            elseIfInvitablePhoneNumbers: { _ in .systemContactWithoutSignal },
            elseIfAddablePhoneNumbers: { _ in .nonSystemContact },
            elseIfNoPhoneNumbers: { .noPhoneNumber }
        )
    }

    @objc
    private func updateMode() {
        AssertIsOnMainThread()

        let phoneNumberPartition = Self.phoneNumberPartition(for: contactShare)
        viewMode = Self.viewMode(for: phoneNumberPartition)
        sendablePhoneNumbers = phoneNumberPartition.sendablePhoneNumbers
    }

    private func showInviteToSignal() -> Bool {
        switch viewMode {
        case .systemContactWithoutSignal, .nonSystemContact:
            return true
        default:
            return false
        }
    }

    private func showAddToContacts() -> Bool {
        switch viewMode {
        case .nonSystemContact, .noPhoneNumber:
            return true
        default:
            return false
        }
    }

    private func updateContent() {
        AssertIsOnMainThread()

        var sections = [OWSTableSection]()

        // Header
        let headerSection = OWSTableSection(items: [], headerView: buildHeaderView())
        sections.append(headerSection)

        // Contact Actions
        let actionsSection = OWSTableSection()

        // Message, Video, Audio buttons for Signal contacts as a horizontal stack of buttons
        if viewMode == .systemContactWithSignal {
            let buttonMessage = SettingsHeaderButton(
                text: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MESSAGE_BUTTON",
                    comment: "Button to message the chat"
                ),
                icon: .settingsChats,
                backgroundColor: Theme.tableCell2BackgroundColor,
                isEnabled: true,
                block: { [weak self] in
                    self?.didPressSendMessage()
                }
            )
            let buttonVideoCall = SettingsHeaderButton(
                text: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_VIDEO_CALL_BUTTON",
                    comment: "Button to start a video call"
                ),
                icon: .buttonVideoCall,
                backgroundColor: Theme.tableCell2BackgroundColor,
                isEnabled: true,
                block: { [weak self] in
                    self?.didPressVideoCall()
                }
            )
            let buttonAudioCall = SettingsHeaderButton(
                text: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_AUDIO_CALL_BUTTON",
                    comment: "Button to start a audio call"
                ),
                icon: .buttonVoiceCall,
                backgroundColor: Theme.tableCell2BackgroundColor,
                isEnabled: true,
                block: { [weak self] in
                    self?.didPressAudioCall()
                }
            )
            let buttonStack = UIStackView(arrangedSubviews: [ buttonMessage, buttonVideoCall, buttonAudioCall ])
            buttonStack.axis = .horizontal
            buttonStack.spacing = 8
            buttonStack.distribution = .fillEqually

            let sectionHeaderView = UIView()
            sectionHeaderView.addSubview(buttonStack)
            buttonStack.autoPinHeightToSuperview()
            buttonStack.autoHCenterInSuperview()
            buttonStack.autoPinWidthToSuperviewMargins(relation: .lessThanOrEqual)
            actionsSection.customHeaderView = sectionHeaderView
        }

        if showInviteToSignal() {
            actionsSection.add(.disclosureItem(
                icon: .settingsInvite,
                name: OWSLocalizedString("ACTION_INVITE", comment: ""),
                accessibilityIdentifier: "invite_contact_share",
                actionBlock: { [weak self] in
                    self?.didPressInvite()
                }
            ))
        }

        if showAddToContacts() {
            actionsSection.add(.disclosureItem(
                icon: .contactInfoAddToContacts,
                name: OWSLocalizedString(
                    "CONVERSATION_VIEW_ADD_TO_CONTACTS_OFFER",
                    comment: "")
                ,
                accessibilityIdentifier: "add_to_contacts",
                actionBlock: { [weak self] in
                    self?.didPressAddToContacts()
                }
            ))
        }

        if actionsSection.customHeaderView != nil || !actionsSection.items.isEmpty {
            sections.append(actionsSection)
        }

        // Contact Info
        let infoSection = OWSTableSection()
        infoSection.add(items: contactShare.phoneNumbers.map({ phoneNumber in
            return OWSTableItem(
                customCellBlock: {
                    return Self.buildPhoneNumberCell(phoneNumber)
                },
                actionBlock: { [weak self] in
                    self?.didPressPhoneNumber(phoneNumber: phoneNumber)
                }
            )
        }))
        infoSection.add(items: contactShare.emails.map({ email in
            return OWSTableItem(
                customCellBlock: {
                    return Self.buildEmailCell(email)
                },
                actionBlock: { [weak self] in
                    self?.didPressEmail(email: email)
                }
            )
        }))
        infoSection.add(items: contactShare.addresses.map({ address in
            return OWSTableItem(
                customCellBlock: {
                    return Self.buildAddressCell(address)
                },
                actionBlock: { [weak self] in
                    self?.didPressAddress(address: address)
                }
            )
        }))
        sections.append(infoSection)

        contents = OWSTableContents(sections: sections)
    }

    private func buildHeaderView() -> UIView {
        AssertIsOnMainThread()

        let headerView = UIView.container()
        headerView.preservesSuperviewLayoutMargins = true

        // Contact info
        //           ________
        //          [        ]
        //          [ Avatar ]
        //          [________]
        //            [Name]
        //      [Organization Name]
        //    [Signal Contact Actions]
        //
        let verticalContentStack = UIStackView()
        verticalContentStack.axis = .vertical
        verticalContentStack.spacing = 8
        verticalContentStack.alignment = .center
        headerView.addSubview(verticalContentStack)
        verticalContentStack.autoPinEdge(toSuperviewEdge: .top, withInset: 20)
        verticalContentStack.autoPinWidthToSuperviewMargins()
        verticalContentStack.autoPinEdge(toSuperviewEdge: .bottom, withInset: 24)

        // Avatar
        let avatarSize: CGFloat = 100
        let avatarView = AvatarImageView()
        avatarView.image = contactShare.getAvatarImageWithSneakyTransaction(diameter: avatarSize)
        avatarView.autoSetDimension(.width, toSize: avatarSize)
        avatarView.autoSetDimension(.height, toSize: avatarSize)
        verticalContentStack.addArrangedSubview(avatarView)

        // Name
        let nameLabel = UILabel()
        nameLabel.text = contactShare.displayName
        // 26pt with default size
        let fontPointSize = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title1).pointSize - 2
        nameLabel.font = UIFont.semiboldFont(ofSize: fontPointSize)
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.lineBreakMode = .byWordWrapping
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 5
        verticalContentStack.addArrangedSubview(nameLabel)

        // Organization Name
        if let organizationName = contactShare.name.organizationName?.ows_stripped().nilIfEmpty,
           contactShare.name.hasAnyNamePart {
            let label = UILabel()
            label.text = organizationName
            label.font = .dynamicTypeSubheadline
            label.textColor = Theme.secondaryTextAndIconColor
            label.lineBreakMode = .byWordWrapping
            label.textAlignment = .center
            label.numberOfLines = 3
            verticalContentStack.addArrangedSubview(label)
        }

        return headerView
    }

    // MARK: Custom cells

    private class func buildTableViewCellWith(_ fieldContentView: UIView) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.contentView.addSubview(fieldContentView)
        fieldContentView.autoPinHeightToSuperview(withMargin: 10)
        fieldContentView.autoPinWidthToSuperviewMargins()
        return cell
    }

    private class func buildPhoneNumberCell(_ phoneNumber: OWSContactPhoneNumber) -> UITableViewCell {
        let fieldContentView = ContactFieldViewHelper.contactFieldView(forPhoneNumber: phoneNumber)
        return buildTableViewCellWith(fieldContentView)
    }

    private class func buildEmailCell(_ email: OWSContactEmail) -> UITableViewCell {
        let fieldContentView = ContactFieldViewHelper.contactFieldView(forEmail: email)
        return buildTableViewCellWith(fieldContentView)
    }

    private class func buildAddressCell(_ address: OWSContactAddress) -> UITableViewCell {
        let fieldContentView = ContactFieldViewHelper.contactFieldView(forAddress: address)
        return buildTableViewCellWith(fieldContentView)
    }
}

// MARK: Actions

extension ContactViewController {

    private func didPressSendMessage() {
        Logger.info("")

        contactShareViewHelper.sendMessage(to: sendablePhoneNumbers, from: self)
    }

    private func didPressAudioCall() {
        Logger.info("")

        contactShareViewHelper.audioCall(to: sendablePhoneNumbers, from: self)
    }

    private func didPressVideoCall() {
        Logger.info("")

        contactShareViewHelper.videoCall(to: sendablePhoneNumbers, from: self)
    }

    private func didPressInvite() {
        Logger.info("")

        contactShareViewHelper.showInviteContact(contactShare: contactShare, from: self)
    }

    private func didPressAddToContacts() {
        Logger.info("")

        contactShareViewHelper.showAddToContactsPrompt(contactShare: contactShare, from: self)
    }

    private func didPressPhoneNumber(phoneNumber: OWSContactPhoneNumber) {
        Logger.info("")

        let actionSheet = ActionSheetController(title: nil, message: nil)

        if let phoneNumber = phoneNumber.e164 {
            let isRegistered = sendablePhoneNumbers.contains(phoneNumber)
            if isRegistered {
                func addAction(title: String, action: ConversationViewAction) {
                    actionSheet.addAction(ActionSheetAction(
                        title: title,
                        style: .default,
                        handler: { _ in
                            let address = SignalServiceAddress(phoneNumber: phoneNumber)
                            SignalApp.shared.presentConversationForAddress(address, action: action, animated: true)
                        }
                    ))
                }
                addAction(title: CommonStrings.sendMessage, action: .compose)
                addAction(
                    title: OWSLocalizedString(
                        "ACTION_AUDIO_CALL",
                        comment: "Label for 'voice call' button in contact view."
                    ),
                    action: .audioCall
                )
                addAction(
                    title: OWSLocalizedString(
                        "ACTION_VIDEO_CALL",
                        comment: "Label for 'video call' button in contact view."
                    ),
                    action: .audioCall
                )
            } else {
                // TODO: We could offer callPhoneNumberWithSystemCall.
            }
        }
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "EDIT_ITEM_COPY_ACTION",
                comment: "Short name for edit menu item to copy contents of media message."
            ),
            style: .default
        ) { _ in
            UIPasteboard.general.string = phoneNumber.phoneNumber
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func callPhoneNumberWithSystemCall(phoneNumber: OWSContactPhoneNumber) {
        Logger.info("")

        guard let url = NSURL(string: "tel:\(phoneNumber.phoneNumber)") else {
            owsFailDebug("could not open phone number.")
            return
        }
        UIApplication.shared.open(url as URL, options: [:])
    }

    private func didPressEmail(email: OWSContactEmail) {
        Logger.info("")

        let actionSheet = ActionSheetController(title: nil, message: nil)
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "CONTACT_VIEW_OPEN_EMAIL_IN_EMAIL_APP",
                comment: "Label for 'open email in email app' button in contact view."
            ),
            style: .default
        ) { [weak self] _ in
            self?.openEmailInEmailApp(email: email)
        })
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "EDIT_ITEM_COPY_ACTION",
                comment: "Short name for edit menu item to copy contents of media message."
            ),
            style: .default
        ) { _ in
            UIPasteboard.general.string = email.email
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func openEmailInEmailApp(email: OWSContactEmail) {
        Logger.info("")

        guard let url = NSURL(string: "mailto:\(email.email)") else {
            owsFailDebug("could not open email.")
            return
        }
        UIApplication.shared.open(url as URL, options: [:])
    }

    private func didPressAddress(address: OWSContactAddress) {
        Logger.info("")

        let actionSheet = ActionSheetController(title: nil, message: nil)
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "CONTACT_VIEW_OPEN_ADDRESS_IN_MAPS_APP",
                comment: "Label for 'open address in maps app' button in contact view."
            ),
            style: .default
        ) { [weak self] _ in
            self?.openAddressInMaps(address: address)
        })
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "EDIT_ITEM_COPY_ACTION",
                comment: "Short name for edit menu item to copy contents of media message."
            ),
            style: .default
        ) { [weak self] _ in
            guard let self else { return }
            UIPasteboard.general.string = self.formatAddressForQuery(address: address)
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func openAddressInMaps(address: OWSContactAddress) {
        Logger.info("")

        let mapAddress = formatAddressForQuery(address: address)
        guard let escapedMapAddress = mapAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            owsFailDebug("could not open address.")
            return
        }
        // Note that we use "q" (i.e. query) rather than "address" since we can't assume
        // this is a well-formed address.
        guard let url = URL(string: "http://maps.apple.com/?q=\(escapedMapAddress)") else {
            owsFailDebug("could not open address.")
            return
        }

        UIApplication.shared.open(url as URL, options: [:])
    }

    private func formatAddressForQuery(address: OWSContactAddress) -> String {
        Logger.info("")

        // Open address in Apple Maps app.
        var addressParts = [String]()
        let addAddressPart: ((String?) -> Void) = { (part) in
            guard let part, !part.isEmpty else { return }

            addressParts.append(part)
        }
        addAddressPart(address.street)
        addAddressPart(address.neighborhood)
        addAddressPart(address.city)
        addAddressPart(address.region)
        addAddressPart(address.postcode)
        addAddressPart(address.country)
        return addressParts.joined(separator: ", ")
    }
}

extension ContactViewController: ContactShareViewHelperDelegate {

    func didCreateOrEditContact() {
        updateContent()
    }
}

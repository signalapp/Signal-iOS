//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import LibSignalClient
import MessageUI
import SignalServiceKit
import SignalUI

class ContactViewController: OWSTableViewController2 {

    private enum ContactViewMode: Equatable {
        case aciShare(aci: Aci)
        case systemContactWithSignal
        case systemContactWithoutSignal
        case nonSystemContact
        case noPhoneNumber
    }

    private var viewMode: ContactViewMode {
        didSet {
            AssertIsOnMainThread()

            if oldValue != viewMode, isViewLoaded {
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

    init(contactShare: ContactShareViewModel) {
        self.contactShare = contactShare
        let phoneNumberPartition = Self.phoneNumberPartition(for: contactShare)
        self.viewMode = Self.viewMode(for: contactShare, phoneNumberPartition: phoneNumberPartition)
        self.sendablePhoneNumbers = phoneNumberPartition.sendablePhoneNumbers

        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMode),
            name: .OWSContactsManagerSignalAccountsDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMode),
            name: SSKReachability.owsReachabilityDidChange,
            object: nil,
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        updateContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        SSKEnvironment.shared.contactManagerImplRef.requestSystemContactsOnce { [weak self] _ in
            self?.updateMode()
        }
    }

    // MARK: Contact Data

    private static func phoneNumberPartition(for contactShare: ContactShareViewModel) -> OWSContact.PhoneNumberPartition {
        return SSKEnvironment.shared.databaseStorageRef.read(block: contactShare.dbRecord.phoneNumberPartition(tx:))
    }

    private static func viewMode(
        for contactShare: ContactShareViewModel,
        phoneNumberPartition: OWSContact.PhoneNumberPartition,
    ) -> ContactViewMode {
        if let aci = contactShare.dbRecord.aci {
            return .aciShare(aci: aci)
        }
        return phoneNumberPartition.map(
            ifSendablePhoneNumbers: { _ in .systemContactWithSignal },
            elseIfInvitablePhoneNumbers: { _ in .systemContactWithoutSignal },
            elseIfAddablePhoneNumbers: { _ in .nonSystemContact },
            elseIfNoPhoneNumbers: { .noPhoneNumber },
        )
    }

    @objc
    private func updateMode() {
        AssertIsOnMainThread()

        let phoneNumberPartition = Self.phoneNumberPartition(for: contactShare)
        sendablePhoneNumbers = phoneNumberPartition.sendablePhoneNumbers
        viewMode = Self.viewMode(for: contactShare, phoneNumberPartition: phoneNumberPartition)
    }

    private func showInviteToSignal() -> Bool {
        switch viewMode {
        case .systemContactWithoutSignal, .nonSystemContact:
            return true
        default:
            return false
        }
    }

    private var isLocalUser: Bool {
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            return false
        }
        if let sharedAci {
            return sharedAci == localIdentifiers.aci
        }
        return sendablePhoneNumbers.contains(where: localIdentifiers.contains(phoneNumber:))
    }

    private func canAddToGroup(aci: Aci) -> Bool {
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            return ThreadFinder().existsGroupThread(transaction: tx)
                && !SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(SignalServiceAddress(aci), transaction: tx)
        }
    }

    private var sharedAci: Aci? {
        switch viewMode {
        case .aciShare(let aci):
            return aci
        case .systemContactWithSignal, .systemContactWithoutSignal, .nonSystemContact, .noPhoneNumber:
            return nil
        }
    }

    private func updateContent() {
        AssertIsOnMainThread()

        var sections = [OWSTableSection]()
        let isLocalUser = self.isLocalUser

        // Header
        let headerSection = OWSTableSection(items: [], headerView: buildHeaderView())
        sections.append(headerSection)

        // Contact Actions
        let actionsSection = OWSTableSection()

        if showInviteToSignal() {
            actionsSection.add(.disclosureItem(
                icon: .settingsInvite,
                withText: OWSLocalizedString("ACTION_INVITE", comment: ""),
                actionBlock: { [weak self] in
                    self?.didPressInvite()
                },
            ))
        }

        actionsSection.add(.disclosureItem(
            icon: .contactInfoAddToContacts,
            withText: OWSLocalizedString(
                "CONVERSATION_VIEW_ADD_TO_CONTACTS_OFFER",
                comment: "",
            )
            ,
            actionBlock: { [weak self] in
                self?.didPressAddToContacts()
            },
        ))

        if let sharedAci, !isLocalUser, canAddToGroup(aci: sharedAci) {
            actionsSection.add(.disclosureItem(
                icon: .contactInfoAddToGroup,
                withText: OWSLocalizedString("ADD_TO_GROUP_TITLE", comment: "Title of the 'add to group' view."),
                actionBlock: { [weak self] in
                    self?.didPressAddToGroup(aci: sharedAci)
                },
            ))
        }

        // Message, Video, Audio buttons for Signal contacts as a horizontal stack of buttons
        if sharedAci != nil || viewMode == .systemContactWithSignal {
            let buttonMessage = SettingsHeaderButton(
                title: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MESSAGE_BUTTON",
                    comment: "Button to message the chat",
                ).capitalized,
                icon: .settingsChats,
            ) { [weak self] in
                self?.didPressSendMessage()
            }
            let buttonVideoCall = SettingsHeaderButton(
                title: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_VIDEO_CALL_BUTTON",
                    comment: "Button to start a video call",
                ).capitalized,
                icon: .buttonVideoCall,
            ) { [weak self] in
                self?.didPressVideoCall()
            }
            let buttonAudioCall = SettingsHeaderButton(
                title: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_VOICE_CALL_BUTTON",
                    comment: "Button to start a voice call",
                ).capitalized,
                icon: .buttonVoiceCall,
            ) { [weak self] in
                self?.didPressAudioCall()
            }
            let buttonStack = UIStackView(arrangedSubviews: isLocalUser ? [buttonMessage] : [buttonMessage, buttonVideoCall, buttonAudioCall])
            buttonStack.axis = .horizontal
            buttonStack.spacing = 8
            buttonStack.distribution = .fillEqually

            let sectionHeaderView = UIView()
            sectionHeaderView.addSubview(buttonStack)
            buttonStack.autoPinEdge(toSuperviewEdge: .top)
            buttonStack.autoPinEdge(
                toSuperviewEdge: .bottom,
                withInset: actionsSection.items.isEmpty ? 0 : defaultSpacingBetweenSections ?? 0,
            )
            buttonStack.autoHCenterInSuperview()
            buttonStack.autoPinWidthToSuperviewMargins(relation: .lessThanOrEqual)
            actionsSection.customHeaderView = sectionHeaderView
        }

        if actionsSection.customHeaderView != nil || !actionsSection.items.isEmpty {
            sections.append(actionsSection)
        }

        // Contact Info
        let infoSection = OWSTableSection()
        infoSection.add(items: contactShare.phoneNumbers.map({ phoneNumber in
            let menuActions = phoneNumberMenuActions(phoneNumber: phoneNumber)
            return OWSTableItem(customCellBlock: {
                return Self.buildPhoneNumberCell(phoneNumber, menuActions: menuActions)
            })
        }))
        infoSection.add(items: contactShare.emails.map({ email in
            let menuActions = emailMenuActions(email: email)
            return OWSTableItem(customCellBlock: {
                return Self.buildEmailCell(email, menuActions: menuActions)
            })
        }))
        infoSection.add(items: contactShare.addresses.map({ address in
            let menuActions = addressMenuActions(address: address)
            return OWSTableItem(customCellBlock: {
                return Self.buildAddressCell(address, menuActions: menuActions)
            })
        }))
        if let nickname = contactShare.nickname {
            let menuActions = [copyAction(text: OWSFormat.formatNameComponents(nickname))]
            infoSection.add(OWSTableItem(customCellBlock: {
                return Self.buildNicknameCell(nickname, menuActions: menuActions)
            }))
        }
        if let note = contactShare.note {
            let menuActions = [copyAction(text: note)]
            infoSection.add(OWSTableItem(customCellBlock: {
                return Self.buildNoteCell(note, menuActions: menuActions)
            }))
        }
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
        if
            let organizationName = contactShare.name.organizationName?.ows_stripped().nilIfEmpty,
            contactShare.name.hasAnyNamePart
        {
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

    private class func buildTableViewCellWith(_ fieldContentView: UIView, menuActions: [UIMenuElement]) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.contentView.addSubview(fieldContentView)
        fieldContentView.autoPinHeightToSuperview(withMargin: 10)
        fieldContentView.autoPinWidthToSuperviewMargins()

        let contextMenuButton = ContextMenuButton(actions: menuActions)
        contextMenuButton.accessibilityLabel = fieldContentView.subviews
            .compactMap { $0.accessibilityLabel?.strippedOrNil }
            .joined(separator: ", ")
        cell.addSubview(contextMenuButton)
        contextMenuButton.autoPinEdgesToSuperviewEdges()

        return cell
    }

    private class func buildPhoneNumberCell(_ phoneNumber: OWSContactPhoneNumber, menuActions: [UIMenuElement]) -> UITableViewCell {
        let fieldContentView = ContactFieldViewHelper.contactFieldView(forPhoneNumber: phoneNumber)
        return buildTableViewCellWith(fieldContentView, menuActions: menuActions)
    }

    private class func buildEmailCell(_ email: OWSContactEmail, menuActions: [UIMenuElement]) -> UITableViewCell {
        let fieldContentView = ContactFieldViewHelper.contactFieldView(forEmail: email)
        return buildTableViewCellWith(fieldContentView, menuActions: menuActions)
    }

    private class func buildAddressCell(_ address: OWSContactAddress, menuActions: [UIMenuElement]) -> UITableViewCell {
        let fieldContentView = ContactFieldViewHelper.contactFieldView(forAddress: address)
        return buildTableViewCellWith(fieldContentView, menuActions: menuActions)
    }

    private class func buildNicknameCell(_ nickname: PersonNameComponents, menuActions: [UIMenuElement]) -> UITableViewCell {
        let fieldContentView = ContactFieldViewHelper.contactFieldView(forNickname: nickname)
        return buildTableViewCellWith(fieldContentView, menuActions: menuActions)
    }

    private class func buildNoteCell(_ note: String, menuActions: [UIMenuElement]) -> UITableViewCell {
        let fieldContentView = ContactFieldViewHelper.contactFieldView(forNote: note)
        return buildTableViewCellWith(fieldContentView, menuActions: menuActions)
    }
}

// MARK: Actions

extension ContactViewController {

    private func didPressSendMessage() {
        if let sharedAci {
            contactShareViewHelper.sendMessage(toAci: sharedAci, sharedName: contactShare.dbRecord.name)
        } else {
            contactShareViewHelper.sendMessage(to: sendablePhoneNumbers, from: self)
        }
    }

    private func didPressAudioCall() {
        if let sharedAci {
            contactShareViewHelper.audioCall(toAci: sharedAci, sharedName: contactShare.dbRecord.name)
        } else {
            contactShareViewHelper.audioCall(to: sendablePhoneNumbers, from: self)
        }
    }

    private func didPressVideoCall() {
        if let sharedAci {
            contactShareViewHelper.videoCall(toAci: sharedAci, sharedName: contactShare.dbRecord.name)
        } else {
            contactShareViewHelper.videoCall(to: sendablePhoneNumbers, from: self)
        }
    }

    private func didPressInvite() {
        contactShareViewHelper.showInviteContact(contactShare: contactShare, from: self)
    }

    private func didPressAddToContacts() {
        contactShareViewHelper.showAddToContactsPrompt(contactShare: contactShare, from: self)
    }

    private func didPressAddToGroup(aci: Aci) {
        contactShareViewHelper.showAddToGroup(aci: aci, sharedName: contactShare.dbRecord.name, fromViewController: self)
    }

    private func phoneNumberMenuActions(phoneNumber: OWSContactPhoneNumber) -> [UIMenuElement] {
        return [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.signalPhoneNumberActions(phoneNumber: phoneNumber) ?? [])
            },
            copyAction(text: phoneNumber.phoneNumber),
        ]
    }

    private func signalPhoneNumberActions(phoneNumber: OWSContactPhoneNumber) -> [UIMenuElement] {
        guard let e164 = phoneNumber.e164, sendablePhoneNumbers.contains(e164) else {
            // TODO: We could offer callPhoneNumberWithSystemCall.
            return []
        }
        func action(title: String, icon: ThemeIcon, action: ConversationViewAction) -> UIAction {
            return UIAction(title: title, image: Theme.iconImage(icon)) { _ in
                let address = SignalServiceAddress(phoneNumber: e164)
                SignalApp.shared.presentConversationForAddress(address, action: action, animated: true)
            }
        }
        return [
            action(title: CommonStrings.sendMessage, icon: .contextMenuMessage, action: .compose),
            action(
                title: OWSLocalizedString(
                    "ACTION_VOICE_CALL",
                    comment: "Label for 'voice call' button in contact view.",
                ),
                icon: .contextMenuVoiceCall,
                action: .voiceCall,
            ),
            action(
                title: OWSLocalizedString(
                    "ACTION_VIDEO_CALL",
                    comment: "Label for 'video call' button in contact view.",
                ),
                icon: .contextMenuVideoCall,
                action: .videoCall,
            ),
        ]
    }

    private func callPhoneNumberWithSystemCall(phoneNumber: OWSContactPhoneNumber) {
        guard let url = NSURL(string: "tel:\(phoneNumber.phoneNumber)") else {
            owsFailDebug("could not open phone number.")
            return
        }
        UIApplication.shared.open(url as URL, options: [:])
    }

    private func emailMenuActions(email: OWSContactEmail) -> [UIMenuElement] {
        return [
            UIAction(
                title: OWSLocalizedString(
                    "CONTACT_VIEW_OPEN_EMAIL_IN_EMAIL_APP",
                    comment: "Label for 'open email in email app' button in contact view.",
                ),
                image: Theme.iconImage(.contextMenuOpenInChat),
            ) { [weak self] _ in
                self?.openEmailInEmailApp(email: email)
            },
            copyAction(text: email.email),
        ]
    }

    private func openEmailInEmailApp(email: OWSContactEmail) {
        guard let url = NSURL(string: "mailto:\(email.email)") else {
            owsFailDebug("could not open email.")
            return
        }
        UIApplication.shared.open(url as URL, options: [:])
    }

    private func copyAction(text: String) -> UIAction {
        return UIAction(
            title: OWSLocalizedString(
                "EDIT_ITEM_COPY_ACTION",
                comment: "Short name for edit menu item to copy contents of media message.",
            ),
            image: Theme.iconImage(.contextMenuCopy),
        ) { _ in
            UIPasteboard.general.string = text
        }
    }

    private func addressMenuActions(address: OWSContactAddress) -> [UIMenuElement] {
        return [
            UIAction(
                title: OWSLocalizedString(
                    "CONTACT_VIEW_OPEN_ADDRESS_IN_MAPS_APP",
                    comment: "Label for 'open address in maps app' button in contact view.",
                ),
                image: Theme.iconImage(.contextMenuOpenInChat),
            ) { [weak self] _ in
                self?.openAddressInMaps(address: address)
            },
            copyAction(text: formatAddressForQuery(address: address)),
        ]
    }

    private func openAddressInMaps(address: OWSContactAddress) {
        let mapAddress = formatAddressForQuery(address: address)
        guard let escapedMapAddress = mapAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            owsFailDebug("could not open address.")
            return
        }
        // Note that we use "q" (i.e. query) rather than "address" since we can't assume
        // this is a well-formed address.
        guard let url = URL(string: "maps://?q=\(escapedMapAddress)") else {
            owsFailDebug("could not open address.")
            return
        }

        UIApplication.shared.open(url as URL, options: [:])
    }

    private func formatAddressForQuery(address: OWSContactAddress) -> String {
        // Open address in Apple Maps app.
        var addressParts = [String]()
        let addAddressPart: ((String?) -> Void) = { part in
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

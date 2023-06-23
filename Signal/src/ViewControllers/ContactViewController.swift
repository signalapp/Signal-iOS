//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import MessageUI
import SignalMessaging
import SignalServiceKit
import SignalUI

class ContactViewController: OWSViewController, ContactShareViewHelperDelegate, OWSNavigationChildController {

    enum ContactViewMode {
        case systemContactWithSignal,
        systemContactWithoutSignal,
        nonSystemContact,
        noPhoneNumber,
        unknown
    }

    private var hasLoadedView = false

    private var viewMode = ContactViewMode.unknown {
        didSet {
            AssertIsOnMainThread()

            if oldValue != viewMode && hasLoadedView {
                updateContent()
            }
        }
    }

    private let contactShare: ContactShareViewModel

    private var contactShareViewHelper: ContactShareViewHelper

    // MARK: - Initializers

    required init(contactShare: ContactShareViewModel) {
        self.contactShare = contactShare
        self.contactShareViewHelper = ContactShareViewHelper()

        super.init()

        contactShareViewHelper.delegate = self

        updateMode()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateMode),
                                               name: .OWSContactsManagerSignalAccountsDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateMode),
                                               name: SSKReachability.owsReachabilityDidChange,
                                               object: nil)
    }

    // MARK: - View Lifecycle

    var prefersNavigationBarHidden: Bool { true }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        contactsManagerImpl.requestSystemContactsOnce { [weak self] _ in
            self?.updateMode()
        }
    }

    override func loadView() {
        super.loadView()

        self.view.preservesSuperviewLayoutMargins = false
        self.view.backgroundColor = heroBackgroundColor()

        updateContent()

        hasLoadedView = true
    }

    @objc
    private func updateMode() {
        AssertIsOnMainThread()

        guard contactShare.e164PhoneNumbers().count > 0 else {
            viewMode = .noPhoneNumber
            return
        }
        if systemContactsWithSignalAccountsForContact().count > 0 {
            viewMode = .systemContactWithSignal
            return
        }
        if systemContactsForContact().count > 0 {
            viewMode = .systemContactWithoutSignal
            return
        }

        viewMode = .nonSystemContact
    }

    private func systemContactsWithSignalAccountsForContact() -> [String] {
        AssertIsOnMainThread()

        return contactShare.systemContactsWithSignalAccountPhoneNumbers()
    }

    private func systemContactsForContact() -> [String] {
        AssertIsOnMainThread()

        return databaseStorage.read { transaction in
            contactShare.systemContactPhoneNumbers(transaction: transaction)
        }
    }

    private func updateContent() {
        AssertIsOnMainThread()

        guard let rootView = self.view else {
            owsFailDebug("missing root view.")
            return
        }

        for subview in rootView.subviews {
            subview.removeFromSuperview()
        }

        let topView = createTopView()
        rootView.addSubview(topView)
        topView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        topView.autoPinWidthToSuperview()

        // This view provides a background "below the fold".
        let bottomView = UIView.container()
        bottomView.backgroundColor = Theme.backgroundColor
        self.view.addSubview(bottomView)
        bottomView.layoutMargins = .zero
        bottomView.autoPinWidthToSuperview()
        bottomView.autoPinEdge(.top, to: .bottom, of: topView)
        bottomView.autoPinEdge(toSuperviewEdge: .bottom)

        let scrollView = UIScrollView()
        scrollView.preservesSuperviewLayoutMargins = false
        self.view.addSubview(scrollView)
        scrollView.layoutMargins = .zero
        scrollView.autoPinWidthToSuperview()
        scrollView.autoPinEdge(.top, to: .bottom, of: topView)
        scrollView.autoPinEdge(toSuperviewEdge: .bottom)

        let fieldsView = createFieldsView()

        scrollView.addSubview(fieldsView)
        fieldsView.autoPinLeadingToSuperviewMargin()
        fieldsView.autoPinTrailingToSuperviewMargin()
        fieldsView.autoPinEdge(toSuperviewEdge: .top)
        fieldsView.autoPinEdge(toSuperviewEdge: .bottom)
    }

    private func heroBackgroundColor() -> UIColor {
        return (Theme.isDarkThemeEnabled
        ? UIColor(rgbHex: 0x272727)
        : UIColor(rgbHex: 0xefeff4))
    }

    private func createTopView() -> UIView {
        AssertIsOnMainThread()

        let topView = UIView.container()
        topView.backgroundColor = heroBackgroundColor()
        topView.preservesSuperviewLayoutMargins = false

        // Back Button
        let backButtonSize = CGFloat(50)
        let backButton = TappableView(actionBlock: { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.didPressDismiss()
        })
        backButton.autoSetDimension(.width, toSize: backButtonSize)
        backButton.autoSetDimension(.height, toSize: backButtonSize)
        topView.addSubview(backButton)
        backButton.autoPinEdge(toSuperviewEdge: .top)
        backButton.autoPinLeadingToSuperviewMargin()

        let backIconView = UIImageView(image: UIImage(imageLiteralResourceName: "NavBarBack"))
        backIconView.contentMode = .scaleAspectFit
        backIconView.tintColor = Theme.primaryIconColor
        backButton.addSubview(backIconView)
        backIconView.autoCenterInSuperview()

        let avatarSize: CGFloat = 100
        let avatarView = AvatarImageView()
        avatarView.image = contactShare.getAvatarImageWithSneakyTransaction(diameter: avatarSize)
        topView.addSubview(avatarView)
        avatarView.autoPinEdge(toSuperviewEdge: .top, withInset: 20)
        avatarView.autoHCenterInSuperview()
        avatarView.autoSetDimension(.width, toSize: avatarSize)
        avatarView.autoSetDimension(.height, toSize: avatarSize)

        let nameLabel = UILabel()
        nameLabel.text = contactShare.displayName
        nameLabel.font = UIFont.dynamicTypeTitle1
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.textAlignment = .center
        topView.addSubview(nameLabel)
        nameLabel.autoPinEdge(.top, to: .bottom, of: avatarView, withOffset: 10)
        nameLabel.autoPinLeadingToSuperviewMargin(withInset: hMargin)
        nameLabel.autoPinTrailingToSuperviewMargin(withInset: hMargin)

        var lastView: UIView = nameLabel

        for phoneNumber in systemContactsWithSignalAccountsForContact() {
            let phoneNumberLabel = UILabel()
            phoneNumberLabel.text = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber)
            phoneNumberLabel.font = UIFont.dynamicTypeFootnote
            phoneNumberLabel.textColor = Theme.primaryTextColor
            phoneNumberLabel.lineBreakMode = .byTruncatingTail
            phoneNumberLabel.textAlignment = .center
            topView.addSubview(phoneNumberLabel)
            phoneNumberLabel.autoPinEdge(.top, to: .bottom, of: lastView, withOffset: 5)
            phoneNumberLabel.autoPinLeadingToSuperviewMargin(withInset: hMargin)
            phoneNumberLabel.autoPinTrailingToSuperviewMargin(withInset: hMargin)
            lastView = phoneNumberLabel
        }

        switch viewMode {
        case .systemContactWithSignal:
            // Show actions buttons for system contacts with a Signal account.
            let stackView = UIStackView()
            stackView.axis = .horizontal
            stackView.distribution = .fillEqually
            stackView.addArrangedSubview(createCircleActionButton(
                text: CommonStrings.sendMessage,
                image: Theme.iconImage(.buttonMessage),
                actionBlock: { [weak self] in
                    guard let strongSelf = self else { return }
                    strongSelf.didPressSendMessage()
                }
            ))
            stackView.addArrangedSubview(createCircleActionButton(
                text: OWSLocalizedString("ACTION_AUDIO_CALL",
                                         comment: "Label for 'voice call' button in contact view."),
                image: Theme.iconImage(.buttonVoiceCall),
                actionBlock: { [weak self] in
                    guard let strongSelf = self else { return }
                    strongSelf.didPressAudioCall()
                }
            ))
            stackView.addArrangedSubview(createCircleActionButton(
                text: OWSLocalizedString("ACTION_VIDEO_CALL",
                                         comment: "Label for 'video call' button in contact view."),
                image: Theme.iconImage(.buttonVideoCall),
                actionBlock: { [weak self] in
                    guard let strongSelf = self else { return }
                    strongSelf.didPressVideoCall()
                }
            ))
            topView.addSubview(stackView)
            stackView.autoPinEdge(.top, to: .bottom, of: lastView, withOffset: 20)
            stackView.autoPinLeadingToSuperviewMargin(withInset: hMargin)
            stackView.autoPinTrailingToSuperviewMargin(withInset: hMargin)
            lastView = stackView
        case .systemContactWithoutSignal:
            // Show invite button for system contacts without a Signal account.
            let inviteButton = createLargePillButton(text: OWSLocalizedString("ACTION_INVITE",
                                                                             comment: "Label for 'invite' button in contact view."),
                                                     actionBlock: { [weak self] in
                                                        guard let strongSelf = self else { return }
                                                        strongSelf.didPressInvite()
            })
            topView.addSubview(inviteButton)
            inviteButton.autoPinEdge(.top, to: .bottom, of: lastView, withOffset: 20)
            inviteButton.autoPinLeadingToSuperviewMargin(withInset: 55)
            inviteButton.autoPinTrailingToSuperviewMargin(withInset: 55)
            lastView = inviteButton
        case .nonSystemContact:
            // Show no action buttons for non-system contacts.
            break
        case .noPhoneNumber:
            // Show no action buttons for contacts without a phone number.
            break
        case .unknown:
            let activityIndicator = UIActivityIndicatorView(style: .large)
            topView.addSubview(activityIndicator)
            activityIndicator.autoPinEdge(.top, to: .bottom, of: lastView, withOffset: 10)
            activityIndicator.autoHCenterInSuperview()
            lastView = activityIndicator
        }

        // Always show "add to contacts" button.
        let addToContactsButton = createLargePillButton(text: OWSLocalizedString("CONVERSATION_VIEW_ADD_TO_CONTACTS_OFFER",
                                                                                comment: "Message shown in conversation view that offers to add an unknown user to your phone's contacts."),
                                                        actionBlock: { [weak self] in
                                                            guard let strongSelf = self else { return }
                                                            strongSelf.didPressAddToContacts()
        })
        topView.addSubview(addToContactsButton)
        addToContactsButton.autoPinEdge(.top, to: .bottom, of: lastView, withOffset: 20)
        addToContactsButton.autoPinLeadingToSuperviewMargin(withInset: 55)
        addToContactsButton.autoPinTrailingToSuperviewMargin(withInset: 55)
        lastView = addToContactsButton

        lastView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 15)

        return topView
    }

    private func createFieldsView() -> UIView {
        AssertIsOnMainThread()

        var rows = [UIView]()

        // TODO: Not designed yet.
//        if viewMode == .systemContactWithSignal ||
//           viewMode == .systemContactWithoutSignal {
//            addRow(createActionRow(labelText:OWSLocalizedString("ACTION_SHARE_CONTACT",
//                                                               comment:"Label for 'share contact' button."),
//                                   action:#selector(didPressShareContact)))
//        }

        if
            let organizationName = contactShare.name.organizationName?.ows_stripped().nilIfEmpty,
            contactShare.name.hasAnyNamePart()
        {
            rows.append(ContactFieldView.contactFieldView(forOrganizationName: organizationName,
                                                          layoutMargins: UIEdgeInsets(top: 5, left: hMargin, bottom: 5, right: hMargin)))
        }

        for phoneNumber in contactShare.phoneNumbers {
            rows.append(ContactFieldView.contactFieldView(forPhoneNumber: phoneNumber,
                                                          layoutMargins: UIEdgeInsets(top: 5, left: hMargin, bottom: 5, right: hMargin),
                                                          actionBlock: { [weak self] in
                                                            guard let strongSelf = self else { return }
                                                            strongSelf.didPressPhoneNumber(phoneNumber: phoneNumber)
            }))
        }

        for email in contactShare.emails {
            rows.append(ContactFieldView.contactFieldView(forEmail: email,
                                                          layoutMargins: UIEdgeInsets(top: 5, left: hMargin, bottom: 5, right: hMargin),
                                                          actionBlock: { [weak self] in
                                                            guard let strongSelf = self else { return }
                                                            strongSelf.didPressEmail(email: email)
            }))
        }

        for address in contactShare.addresses {
            rows.append(ContactFieldView.contactFieldView(forAddress: address,
                                                          layoutMargins: UIEdgeInsets(top: 5, left: hMargin, bottom: 5, right: hMargin),
                                                          actionBlock: { [weak self] in
                                                            guard let strongSelf = self else { return }
                                                            strongSelf.didPressAddress(address: address)
            }))
        }

        return ContactFieldView(rows: rows, hMargin: hMargin)
    }

    private let hMargin = CGFloat(16)

    private func createActionRow(labelText: String, action: Selector) -> UIView {
        let row = UIView()
        row.layoutMargins.left = 0
        row.layoutMargins.right = 0
        row.isUserInteractionEnabled = true
        row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: action))

        let label = UILabel()
        label.text = labelText
        label.font = UIFont.dynamicTypeBody
        label.textColor = Theme.accentBlueColor
        label.lineBreakMode = .byTruncatingTail
        row.addSubview(label)
        label.autoPinTopToSuperviewMargin()
        label.autoPinBottomToSuperviewMargin()
        label.autoPinLeadingToSuperviewMargin(withInset: hMargin)
        label.autoPinTrailingToSuperviewMargin(withInset: hMargin)

        return row
    }

    // TODO: Use real assets.
    private func createCircleActionButton(text: String, image: UIImage, actionBlock: @escaping () -> Void) -> UIView {
        let buttonSize = CGFloat(50)

        let button = TappableView(actionBlock: actionBlock)
        button.layoutMargins = .zero
        button.autoSetDimension(.width, toSize: buttonSize, relation: .greaterThanOrEqual)

        let circleView = CircleView(diameter: buttonSize)
        circleView.backgroundColor = Theme.backgroundColor
        button.addSubview(circleView)
        circleView.autoPinEdge(toSuperviewEdge: .top)
        circleView.autoHCenterInSuperview()

        let imageView = UIImageView(image: image)
        imageView.tintColor = Theme.primaryTextColor.withAlphaComponent(0.6)
        circleView.addSubview(imageView)
        imageView.autoCenterInSuperview()

        let label = UILabel()
        label.text = text
        label.font = UIFont.dynamicTypeCaption2
        label.textColor = Theme.primaryTextColor
        label.lineBreakMode = .byTruncatingTail
        label.textAlignment = .center
        button.addSubview(label)
        label.autoPinEdge(.top, to: .bottom, of: circleView, withOffset: 3)
        label.autoPinEdge(toSuperviewEdge: .bottom)
        label.autoPinLeadingToSuperviewMargin()
        label.autoPinTrailingToSuperviewMargin()

        return button
    }

    private func createLargePillButton(text: String, actionBlock: @escaping () -> Void) -> UIView {
        let button = TappableView(actionBlock: actionBlock)
        button.backgroundColor = Theme.backgroundColor
        button.layoutMargins = .zero
        button.autoSetDimension(.height, toSize: 45)
        button.layer.cornerRadius = 5

        let label = UILabel()
        label.text = text
        label.font = UIFont.dynamicTypeBody
        label.textColor = Theme.accentBlueColor
        label.lineBreakMode = .byTruncatingTail
        label.textAlignment = .center
        button.addSubview(label)
        label.autoPinLeadingToSuperviewMargin(withInset: 20)
        label.autoPinTrailingToSuperviewMargin(withInset: 20)
        label.autoVCenterInSuperview()
        label.autoPinEdge(toSuperviewEdge: .top, withInset: 0, relation: .greaterThanOrEqual)
        label.autoPinEdge(toSuperviewEdge: .bottom, withInset: 0, relation: .greaterThanOrEqual)

        return button
    }

    func didPressShareContact(sender: UIGestureRecognizer) {
        Logger.info("")

        guard sender.state == .recognized else {
            return
        }
        // TODO:
    }

    func didPressSendMessage() {
        Logger.info("")

        self.contactShareViewHelper.sendMessage(contactShare: self.contactShare, fromViewController: self)
    }

    func didPressAudioCall() {
        Logger.info("")

        self.contactShareViewHelper.audioCall(contactShare: self.contactShare, fromViewController: self)
    }

    func didPressVideoCall() {
        Logger.info("")

        self.contactShareViewHelper.videoCall(contactShare: self.contactShare, fromViewController: self)
    }

    func didPressInvite() {
        Logger.info("")

        self.contactShareViewHelper.showInviteContact(contactShare: self.contactShare, fromViewController: self)
    }

    func didPressAddToContacts() {
        Logger.info("")

        self.contactShareViewHelper.showAddToContacts(contactShare: self.contactShare, fromViewController: self)
    }

    func didPressDismiss() {
        Logger.info("")

        guard let navigationController = self.navigationController else {
            owsFailDebug("navigationController was unexpectedly nil")
            return
        }

        navigationController.popViewController(animated: true)
    }

    func didPressPhoneNumber(phoneNumber: OWSContactPhoneNumber) {
        Logger.info("")

        let actionSheet = ActionSheetController(title: nil, message: nil)

        if let e164 = phoneNumber.tryToConvertToE164() {
            let address = SignalServiceAddress(phoneNumber: e164)
            if contactShare.systemContactsWithSignalAccountPhoneNumbers().contains(e164) {
                actionSheet.addAction(ActionSheetAction(
                    title: CommonStrings.sendMessage,
                    style: .default) { _ in
                        SignalApp.shared.presentConversationForAddress(address, action: .compose, animated: true)
                    })
                actionSheet.addAction(ActionSheetAction(
                    title: OWSLocalizedString("ACTION_AUDIO_CALL",
                                              comment: "Label for 'voice call' button in contact view."),
                    style: .default) { _ in
                        SignalApp.shared.presentConversationForAddress(address, action: .audioCall, animated: true)
                    })
                actionSheet.addAction(ActionSheetAction(
                    title: OWSLocalizedString("ACTION_VIDEO_CALL",
                                              comment: "Label for 'video call' button in contact view."),
                    style: .default) { _ in
                        SignalApp.shared.presentConversationForAddress(address, action: .videoCall, animated: true)
                    })
            } else {
                // TODO: We could offer callPhoneNumberWithSystemCall.
            }
        }
        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("EDIT_ITEM_COPY_ACTION",
                                                                     comment: "Short name for edit menu item to copy contents of media message."),
                                            style: .default) { _ in
                                                UIPasteboard.general.string = phoneNumber.phoneNumber
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    func callPhoneNumberWithSystemCall(phoneNumber: OWSContactPhoneNumber) {
        Logger.info("")

        guard let url = NSURL(string: "tel:\(phoneNumber.phoneNumber)") else {
            owsFailDebug("could not open phone number.")
            return
        }
        UIApplication.shared.open(url as URL, options: [:])
    }

    func didPressEmail(email: OWSContactEmail) {
        Logger.info("")

        let actionSheet = ActionSheetController(title: nil, message: nil)
        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("CONTACT_VIEW_OPEN_EMAIL_IN_EMAIL_APP",
                                                                     comment: "Label for 'open email in email app' button in contact view."),
                                            style: .default) { [weak self] _ in
                                                self?.openEmailInEmailApp(email: email)
        })
        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("EDIT_ITEM_COPY_ACTION",
                                                                     comment: "Short name for edit menu item to copy contents of media message."),
                                            style: .default) { _ in
                                                UIPasteboard.general.string = email.email
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    func openEmailInEmailApp(email: OWSContactEmail) {
        Logger.info("")

        guard let url = NSURL(string: "mailto:\(email.email)") else {
            owsFailDebug("could not open email.")
            return
        }
        UIApplication.shared.open(url as URL, options: [:])
    }

    func didPressAddress(address: OWSContactAddress) {
        Logger.info("")

        let actionSheet = ActionSheetController(title: nil, message: nil)
        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("CONTACT_VIEW_OPEN_ADDRESS_IN_MAPS_APP",
                                                                     comment: "Label for 'open address in maps app' button in contact view."),
                                            style: .default) { [weak self] _ in
                                                self?.openAddressInMaps(address: address)
        })
        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("EDIT_ITEM_COPY_ACTION",
                                                                     comment: "Short name for edit menu item to copy contents of media message."),
                                            style: .default) { [weak self] _ in
                                                guard let strongSelf = self else { return }

                                                UIPasteboard.general.string = strongSelf.formatAddressForQuery(address: address)
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    func openAddressInMaps(address: OWSContactAddress) {
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

    func formatAddressForQuery(address: OWSContactAddress) -> String {
        Logger.info("")

        // Open address in Apple Maps app.
        var addressParts = [String]()
        let addAddressPart: ((String?) -> Void) = { (part) in
            guard let part = part else {
                return
            }
            if part.isEmpty {
                return
            }
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

    // MARK: - ContactShareViewHelperDelegate

    public func didCreateOrEditContact() {
        Logger.info("")
        updateContent()

        self.dismiss(animated: true)
    }
}

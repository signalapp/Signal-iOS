//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging
import Reachability
import ContactsUI
import MessageUI

class TappableView: UIView {
    let actionBlock : (() -> Void)

    // MARK: - Initializers

    @available(*, unavailable, message: "use init(call:) constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("Unimplemented")
    }

    required init(actionBlock : @escaping () -> Void) {
        self.actionBlock = actionBlock
        super.init(frame: CGRect.zero)

        self.isUserInteractionEnabled = true
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(wasTapped)))
    }

    func wasTapped(sender: UIGestureRecognizer) {
        Logger.info("\(logTag) \(#function)")

        guard sender.state == .recognized else {
            return
        }
        actionBlock()
    }
}

// MARK: -

class ContactViewController: OWSViewController, CNContactViewControllerDelegate {

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
            SwiftAssertIsOnMainThread(#function)

            if oldValue != viewMode && hasLoadedView {
                updateContent()
            }
        }
    }

    let contactsManager: OWSContactsManager

    var reachability: Reachability?

    private let contact: OWSContact

    // MARK: - Initializers

    @available(*, unavailable, message: "use init(call:) constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("Unimplemented")
    }

    required init(contact: OWSContact) {
        contactsManager = Environment.current().contactsManager
        self.contact = contact

        super.init(nibName: nil, bundle: nil)

        updateMode()

        NotificationCenter.default.addObserver(forName: .OWSContactsManagerSignalAccountsDidChange, object: nil, queue: nil) { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.updateMode()
        }

        reachability = Reachability.forInternetConnection()

        NotificationCenter.default.addObserver(forName: .reachabilityChanged, object: nil, queue: nil) { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.updateMode()
        }
    }

    // MARK: - View Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        UIUtil.applySignalAppearence()

        navigationController?.isNavigationBarHidden = true

        contactsManager.requestSystemContactsOnce(completion: { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.updateMode()
        })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIUtil.applySignalAppearence()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        navigationController?.isNavigationBarHidden = false
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    override func loadView() {
        super.loadView()

        self.view.preservesSuperviewLayoutMargins = false
        self.view.backgroundColor = heroBackgroundColor()

        updateContent()

        hasLoadedView = true
    }

    private func updateMode() {
        SwiftAssertIsOnMainThread(#function)

        guard phoneNumbersForContact().count > 0 else {
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
        SwiftAssertIsOnMainThread(#function)

        return phoneNumbersForContact().filter({ (phoneNumber) -> Bool in
            return contactsManager.hasSignalAccount(forRecipientId: phoneNumber)
        })
    }

    private func systemContactsForContact() -> [String] {
        SwiftAssertIsOnMainThread(#function)

        return phoneNumbersForContact().filter({ (phoneNumber) -> Bool in
            return contactsManager.allContactsMap[phoneNumber] != nil
        })
    }

    private func phoneNumbersForContact() -> [String] {
        SwiftAssertIsOnMainThread(#function)

        var result = [String]()
        for phoneNumber in contact.phoneNumbers {
            result.append(phoneNumber.phoneNumber)
        }
        return result
    }

    private func updateContent() {
        SwiftAssertIsOnMainThread(#function)

        guard let rootView = self.view else {
            owsFail("\(logTag) missing root view.")
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
        bottomView.backgroundColor = UIColor.white
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
        return UIColor(rgbHex: 0xefeff4)
    }

    private func createTopView() -> UIView {
        SwiftAssertIsOnMainThread(#function)

        let topView = UIView.container()
        topView.backgroundColor = heroBackgroundColor()
        topView.preservesSuperviewLayoutMargins = false

        // Back Button
        let backButtonSize = CGFloat(50)
        let backButton = TappableView(actionBlock: { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.didPressDismiss()
        })
        backButton.autoSetDimension(.width, toSize: backButtonSize)
        backButton.autoSetDimension(.height, toSize: backButtonSize)
        topView.addSubview(backButton)
        backButton.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        backButton.autoPinLeadingToSuperviewMargin()

        let backIconName = (self.view.isRTL() ? "system_disclosure_indicator" : "system_disclosure_indicator_rtl")
        guard let backIconImage = UIImage(named: backIconName) else {
            owsFail("\(logTag) missing icon.")
            return topView
        }
        let backIconView = UIImageView(image: backIconImage.withRenderingMode(.alwaysTemplate))
        backIconView.contentMode = .scaleAspectFit
        backIconView.tintColor = UIColor.black.withAlphaComponent(0.6)
        backButton.addSubview(backIconView)
        backIconView.autoCenterInSuperview()

        // TODO: Use actual avatar.
        let avatarSize = CGFloat(100)

        let avatarView = AvatarImageView()
        // TODO: What's the best colorSeed value to use?
        let avatarBuilder = OWSContactAvatarBuilder(nonSignalName: contact.displayName,
                                                    colorSeed: contact.displayName,
                                                    diameter: UInt(avatarSize),
                                                    contactsManager: contactsManager)
        avatarView.image = avatarBuilder.build()
        topView.addSubview(avatarView)
        avatarView.autoPin(toTopLayoutGuideOf: self, withInset: 20)
        avatarView.autoHCenterInSuperview()
        avatarView.autoSetDimension(.width, toSize: avatarSize)
        avatarView.autoSetDimension(.height, toSize: avatarSize)

        let nameLabel = UILabel()
        nameLabel.text = contact.displayName
        nameLabel.font = UIFont.ows_dynamicTypeTitle1
        nameLabel.textColor = UIColor.black
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.textAlignment = .center
        topView.addSubview(nameLabel)
        nameLabel.autoPinEdge(.top, to: .bottom, of: avatarView, withOffset: 10)
        nameLabel.autoPinLeadingToSuperviewMargin(withInset: hMargin)
        nameLabel.autoPinTrailingToSuperviewMargin(withInset: hMargin)

        var lastView: UIView = nameLabel

        for phoneNumber in systemContactsWithSignalAccountsForContact() {
            let phoneNumberLabel = UILabel()
            phoneNumberLabel.text = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: firstPhoneNumber.phoneNumber)
            phoneNumberLabel.font = UIFont.ows_dynamicTypeFootnote
            phoneNumberLabel.textColor = UIColor.black
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
            stackView.addArrangedSubview(createCircleActionButton(text: NSLocalizedString("ACTION_SEND_MESSAGE",
                                                                                          comment: "Label for 'sent message' button in contact view."),
                                                                  actionBlock: { [weak self] _ in
                                                                    guard let strongSelf = self else { return }
                                                                    strongSelf.didPressSendMessage()
            }))
            stackView.addArrangedSubview(createCircleActionButton(text: NSLocalizedString("ACTION_AUDIO_CALL",
                                                                                          comment: "Label for 'audio call' button in contact view."),
                                                                  actionBlock: { [weak self] _ in
                                                                    guard let strongSelf = self else { return }
                                                                    strongSelf.didPressAudioCall()
            }))
            stackView.addArrangedSubview(createCircleActionButton(text: NSLocalizedString("ACTION_VIDEO_CALL",
                                                                                          comment: "Label for 'video call' button in contact view."),
                                                                  actionBlock: { [weak self] _ in
                                                                    guard let strongSelf = self else { return }
                                                                    strongSelf.didPressVideoCall()
            }))
            topView.addSubview(stackView)
            stackView.autoPinEdge(.top, to: .bottom, of: lastView, withOffset: 20)
            stackView.autoPinLeadingToSuperviewMargin(withInset: hMargin)
            stackView.autoPinTrailingToSuperviewMargin(withInset: hMargin)
            lastView = stackView
        case .systemContactWithoutSignal:
            // Show invite button for system contacts without a Signal account.
            let inviteButton = createLargePillButton(text: NSLocalizedString("ACTION_INVITE",
                                                                             comment: "Label for 'invite' button in contact view."),
                                                     actionBlock: { [weak self] _ in
                                                        guard let strongSelf = self else { return }
                                                        strongSelf.didPressInvite()
            })
            topView.addSubview(inviteButton)
            inviteButton.autoPinEdge(.top, to: .bottom, of: lastView, withOffset: 20)
            inviteButton.autoPinLeadingToSuperviewMargin(withInset: 55)
            inviteButton.autoPinTrailingToSuperviewMargin(withInset: 55)
            lastView = inviteButton
        case .nonSystemContact:
            // Show "add to contacts" button for non-system contacts.
            let addToContactsButton = createLargePillButton(text: NSLocalizedString("CONVERSATION_VIEW_ADD_TO_CONTACTS_OFFER",
                                                                                    comment: "Message shown in conversation view that offers to add an unknown user to your phone's contacts."),
                                                     actionBlock: { [weak self] _ in
                                                        guard let strongSelf = self else { return }
                                                        strongSelf.didPressAddToContacts()
            })
            topView.addSubview(addToContactsButton)
            addToContactsButton.autoPinEdge(.top, to: .bottom, of: lastView, withOffset: 20)
            addToContactsButton.autoPinLeadingToSuperviewMargin(withInset: 55)
            addToContactsButton.autoPinTrailingToSuperviewMargin(withInset: 55)
            lastView = addToContactsButton
            break
        case .noPhoneNumber:
            // Show no action buttons for contacts without a phone number.
            break
        case .unknown:
            let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
            topView.addSubview(activityIndicator)
            activityIndicator.autoPinEdge(.top, to: .bottom, of: lastView, withOffset: 10)
            activityIndicator.autoHCenterInSuperview()
            lastView = activityIndicator
            break
        }

        lastView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 15)

        return topView
    }

    private func createFieldsView() -> UIView {
        SwiftAssertIsOnMainThread(#function)

        let fieldsView = UIView.container()
        fieldsView.layoutMargins = .zero
        fieldsView.preservesSuperviewLayoutMargins = false

        var lastRow: UIView?

        let addSpacerRow = {
            guard let prevRow = lastRow else {
                owsFail("\(self.logTag) missing last row")
                return
            }
            let row = UIView()
            row.backgroundColor = UIColor(rgbHex: 0xdedee1)
            fieldsView.addSubview(row)
            row.autoSetDimension(.height, toSize: 1)
            row.autoPinLeadingToSuperviewMargin(withInset: self.hMargin)
            row.autoPinTrailingToSuperviewMargin()
            row.autoPinEdge(.top, to: .bottom, of: prevRow)
            lastRow = row
        }

        let addRow: ((UIView) -> Void) = { (row) in
            if lastRow != nil {
                addSpacerRow()
            }
            fieldsView.addSubview(row)
            row.autoPinLeadingToSuperviewMargin()
            row.autoPinTrailingToSuperviewMargin()
            if let lastRow = lastRow {
                row.autoPinEdge(.top, to: .bottom, of: lastRow)
            } else {
                row.autoPinEdge(toSuperviewEdge: .top)
            }
            lastRow = row
        }

        // TODO: Not designed yet.
//        if viewMode == .systemContactWithSignal ||
//           viewMode == .systemContactWithoutSignal {
//            addRow(createActionRow(labelText:NSLocalizedString("ACTION_SHARE_CONTACT",
//                                                               comment:"Label for 'share contact' button."),
//                                   action:#selector(didPressShareContact)))
//        }

        for phoneNumber in contact.phoneNumbers {
            let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber.phoneNumber)

            addRow(createSimpleFieldRow(name: phoneNumber.localizedLabel(),
                                      value: formattedPhoneNumber,
                                      actionBlock: {
                                        guard let url = NSURL(string: "tel:\(phoneNumber.phoneNumber)") else {
                                            owsFail("\(ContactViewController.logTag) could not open phone number.")
                                            return
                                        }
                                        UIApplication.shared.openURL(url as URL)
            }))
        }

        for email in contact.emails {
            addRow(createSimpleFieldRow(name: email.localizedLabel(),
                                        value: email.email,
                                        actionBlock: {
                                            guard let url = NSURL(string: "mailto:\(email.email)") else {
                                                owsFail("\(ContactViewController.logTag) could not open email.")
                                                return
                                            }
                                            UIApplication.shared.openURL(url as URL)
            }))
        }

        for address in contact.addresses {
            addRow(createAddressFieldRow(name: address.localizedLabel(),
                                        address: address,
                                        actionBlock: { [weak self] _ in
                                            guard let strongSelf = self else { return }
                                            strongSelf.didPressAddress(address: address)
            }))
        }

        lastRow?.autoPinEdge(toSuperviewEdge: .bottom)

        return fieldsView
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
        label.font = UIFont.ows_dynamicTypeBody
        label.textColor = UIColor.ows_materialBlue
        label.lineBreakMode = .byTruncatingTail
        row.addSubview(label)
        label.autoPinTopToSuperviewMargin()
        label.autoPinBottomToSuperviewMargin()
        label.autoPinLeadingToSuperviewMargin(withInset: hMargin)
        label.autoPinTrailingToSuperviewMargin(withInset: hMargin)

        return row
    }

    private func createSimpleFieldRow(name: String, value: String?, actionBlock : @escaping () -> Void) -> UIView {
        let row = TappableView(actionBlock: actionBlock)
        row.layoutMargins.left = 0
        row.layoutMargins.right = 0

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 3
        row.addSubview(stackView)
        stackView.autoPinTopToSuperviewMargin()
        stackView.autoPinBottomToSuperviewMargin()
        stackView.autoPinLeadingToSuperviewMargin(withInset: hMargin)
        stackView.autoPinTrailingToSuperviewMargin(withInset: hMargin)

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = UIFont.ows_dynamicTypeSubheadline
        nameLabel.textColor = UIColor.black
        nameLabel.lineBreakMode = .byTruncatingTail
        stackView.addArrangedSubview(nameLabel)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = UIFont.ows_dynamicTypeBody
        valueLabel.textColor = UIColor.ows_materialBlue
        valueLabel.lineBreakMode = .byTruncatingTail
        stackView.addArrangedSubview(valueLabel)

        return row
    }

    private func createAddressFieldRow(name: String, address: OWSContactAddress, actionBlock : @escaping () -> Void) -> UIView {
        let row = TappableView(actionBlock: actionBlock)
        row.layoutMargins.left = 0
        row.layoutMargins.right = 0

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 3
        stackView.layoutMargins = .zero
        row.addSubview(stackView)
        stackView.autoPinTopToSuperviewMargin()
        stackView.autoPinBottomToSuperviewMargin()
        stackView.autoPinLeadingToSuperviewMargin(withInset: hMargin)
        stackView.autoPinTrailingToSuperviewMargin(withInset: hMargin)

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = UIFont.ows_dynamicTypeSubheadline
        nameLabel.textColor = UIColor.black
        nameLabel.lineBreakMode = .byTruncatingTail
        stackView.addArrangedSubview(nameLabel)

        let tryToAddNameValue: ((String, String?) -> Void) = { (propertyName, propertyValue) in
            guard let propertyValue = propertyValue else {
                return
            }
            guard propertyValue.count > 0 else {
                return
            }

            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .leading
            row.spacing = 10
            row.layoutMargins = .zero

            let nameLabel = UILabel()
            nameLabel.text = propertyName
            nameLabel.font = UIFont.ows_dynamicTypeBody
            nameLabel.textColor = UIColor.black
            nameLabel.lineBreakMode = .byTruncatingTail
            row.addArrangedSubview(nameLabel)
            nameLabel.setContentHuggingHigh()
            nameLabel.setCompressionResistanceHigh()

            let valueLabel = UILabel()
            valueLabel.text = propertyValue
            valueLabel.font = UIFont.ows_dynamicTypeBody
            valueLabel.textColor = UIColor.ows_materialBlue
            valueLabel.lineBreakMode = .byTruncatingTail
            row.addArrangedSubview(valueLabel)

            stackView.addArrangedSubview(row)
        }

        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_STREET", comment: "Label for the 'street' field of a contact's address."),
                          address.street)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_POBOX", comment: "Label for the 'pobox' field of a contact's address."),
                          address.pobox)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_NEIGHBORHOOD", comment: "Label for the 'neighborhood' field of a contact's address."),
                          address.neighborhood)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_CITY", comment: "Label for the 'city' field of a contact's address."),
                          address.city)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_REGION", comment: "Label for the 'region' field of a contact's address."),
                          address.region)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_POSTCODE", comment: "Label for the 'postcode' field of a contact's address."),
                          address.postcode)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_COUNTRY", comment: "Label for the 'country' field of a contact's address."),
                          address.country)

        return row
    }

    // TODO: Use real assets.
    private func createCircleActionButton(text: String, actionBlock : @escaping () -> Void) -> UIView {
        let buttonSize = CGFloat(50)

        let button = TappableView(actionBlock: actionBlock)
        button.layoutMargins = .zero
        button.autoSetDimension(.width, toSize: buttonSize, relation: .greaterThanOrEqual)

        let circleView = UIView()
        circleView.backgroundColor = UIColor.white
        circleView.autoSetDimension(.width, toSize: buttonSize)
        circleView.autoSetDimension(.height, toSize: buttonSize)
        circleView.layer.cornerRadius = buttonSize * 0.5
        button.addSubview(circleView)
        circleView.autoPinEdge(toSuperviewEdge: .top)
        circleView.autoHCenterInSuperview()

        let label = UILabel()
        label.text = text
        label.font = UIFont.ows_dynamicTypeCaption2
        label.textColor = UIColor.black
        label.lineBreakMode = .byTruncatingTail
        label.textAlignment = .center
        button.addSubview(label)
        label.autoPinEdge(.top, to: .bottom, of: circleView, withOffset: 3)
        label.autoPinEdge(toSuperviewEdge: .bottom)
        label.autoPinLeadingToSuperviewMargin()
        label.autoPinTrailingToSuperviewMargin()

        return button
    }

    private func createLargePillButton(text: String, actionBlock : @escaping () -> Void) -> UIView {
        let button = TappableView(actionBlock: actionBlock)
        button.backgroundColor = UIColor.white
        button.layoutMargins = .zero
        button.autoSetDimension(.height, toSize: 45)
        button.layer.cornerRadius = 5

        let label = UILabel()
        label.text = text
        label.font = UIFont.ows_dynamicTypeBody
        label.textColor = UIColor.ows_materialBlue
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

    func didPressCreateNewContact() {
        Logger.info("\(logTag) \(#function)")

        presentNewContactView()
    }

    func didPressAddToExistingContact() {
        Logger.info("\(logTag) \(#function)")

        presentSelectAddToExistingContactView()
    }

    func didPressShareContact(sender: UIGestureRecognizer) {
        Logger.info("\(logTag) \(#function)")

        guard sender.state == .recognized else {
            return
        }
        // TODO:
    }

    func didPressSendMessage() {
        Logger.info("\(logTag) \(#function)")

        presentThreadAndPeform(action: .compose)
    }

    func didPressAudioCall() {
        Logger.info("\(logTag) \(#function)")

        presentThreadAndPeform(action: .audioCall)
    }

    func didPressVideoCall() {
        Logger.info("\(logTag) \(#function)")

        presentThreadAndPeform(action: .videoCall)
    }

    func presentThreadAndPeform(action: ConversationViewAction) {
        // TODO: We're taking the first Signal account id. We might
        // want to let the user select if there's more than one.
        let phoneNumbers = systemContactsWithSignalAccountsForContact()
        guard phoneNumbers.count > 0 else {
            owsFail("\(logTag) missing Signal recipient id.")
            return
        }
        guard phoneNumbers.count > 1 else {
            let recipientId = systemContactsWithSignalAccountsForContact().first!
            SignalApp.shared().presentConversation(forRecipientId: recipientId, action: action)
            return
        }

        showPhoneNumberPicker(phoneNumbers: phoneNumbers, completion: { (recipientId) in
            SignalApp.shared().presentConversation(forRecipientId: recipientId, action: action)
        })
    }

    func didPressInvite() {
        Logger.info("\(logTag) \(#function)")

        guard MFMessageComposeViewController.canSendText() else {
            Logger.info("\(logTag) Device cannot send text")
            OWSAlerts.showErrorAlert(message: NSLocalizedString("UNSUPPORTED_FEATURE_ERROR", comment: ""))
            return
        }
        let phoneNumbers = phoneNumbersForContact()
        guard phoneNumbers.count > 0 else {
            owsFail("\(logTag) no phone numbers.")
            return
        }

        let inviteFlow =
            InviteFlow(presentingViewController: self, contactsManager: contactsManager)
        inviteFlow.sendSMSTo(phoneNumbers: phoneNumbers)
    }

    func didPressAddToContacts() {
        Logger.info("\(logTag) \(#function)")

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("CONVERSATION_SETTINGS_NEW_CONTACT",
                                                                     comment: "Label for 'new contact' button in conversation settings view."),
                                            style: .default) { _ in
                                                self.didPressCreateNewContact()
        })
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
                                                                     comment: "Label for 'new contact' button in conversation settings view."),
                                            style: .default) { _ in
                                                self.didPressAddToExistingContact()
        })
        actionSheet.addAction(OWSAlerts.cancelAction)

        self.present(actionSheet, animated: true)
    }

    private func showPhoneNumberPicker(phoneNumbers: [String], completion :@escaping ((String) -> Void)) {

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        for phoneNumber in phoneNumbers {
            actionSheet.addAction(UIAlertAction(title: PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber),
                                                          style: .default) { _ in
                                                            completion(phoneNumber)
            })
        }
        actionSheet.addAction(OWSAlerts.cancelAction)

        self.present(actionSheet, animated: true)
    }

    func didPressDismiss() {
        Logger.info("\(self.logTag) \(#function)")

        self.navigationController?.popViewController(animated: true)
    }

    func didPressAddress(address: OWSContactAddress) {
        Logger.info("\(self.logTag) \(#function)")

        // Open address in Apple Maps app.
        var addressParts = [String]()
        let addAddressPart: ((String?) -> Void) = { (part) in
            guard let part = part else {
                return
            }
            guard part.count > 0 else {
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
        let mapAddress = addressParts.joined(separator: ", ")
        guard let escapedMapAddress = mapAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            owsFail("\(ContactViewController.logTag) could not open address.")
            return
        }
        // Note that we use "q" (i.e. query) rather than "address" since we can't assume
        // this is a well-formed address.
        guard let url = NSURL(string: "http://maps.apple.com/?q=\(escapedMapAddress)") else {
            owsFail("\(ContactViewController.logTag) could not open address.")
            return
        }

        UIApplication.shared.openURL(url as URL)
    }

    // MARK: -

    private func presentNewContactView() {
        guard contactsManager.supportsContactEditing else {
            owsFail("\(logTag) Contact editing not supported")
            return
        }

        guard let systemContact = OWSContacts.systemContact(for: contact) else {
            owsFail("\(logTag) Could not derive system contact.")
            return
        }

        guard contactsManager.isSystemContactsAuthorized else {
            ContactsViewHelper.presentMissingContactAccessAlertController(from: self)
            return
        }

        let contactViewController = CNContactViewController(forNewContact: systemContact)
        contactViewController.delegate = self
        contactViewController.allowsActions = false
        contactViewController.allowsEditing = true
        contactViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(title: CommonStrings.cancelButton, style: .plain, target: self, action: #selector(didFinishEditingContact))
                contactViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(title: CommonStrings.cancelButton,
                                                                                         style: .plain,
                                                                                         target: self,
                                                                                         action: #selector(didFinishEditingContact))

        self.navigationController?.pushViewController(contactViewController, animated: true)

        // HACK otherwise CNContactViewController Navbar is shown as black.
        // RADAR rdar://28433898 http://www.openradar.me/28433898
        // CNContactViewController incompatible with opaque navigation bar
        UIUtil.applyDefaultSystemAppearence()
    }

    private func presentSelectAddToExistingContactView() {
        guard contactsManager.supportsContactEditing else {
            owsFail("\(logTag) Contact editing not supported")
            return
        }

        guard contactsManager.isSystemContactsAuthorized else {
            ContactsViewHelper.presentMissingContactAccessAlertController(from: self)
            return
        }

        guard let firstPhoneNumber = contact.phoneNumbers.first else {
            owsFail("\(logTag) Missing phone number.")
            return
        }

        // TODO: We need to modify OWSAddToContactViewController to take a OWSContact
        // and merge it with an existing CNContact.
        let viewController = OWSAddToContactViewController()
        viewController.configure(withRecipientId: firstPhoneNumber.phoneNumber)
        self.navigationController?.pushViewController(viewController, animated: true)
    }

    // MARK: - CNContactViewControllerDelegate

    @objc public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        Logger.info("\(logTag) \(#function)")

        self.navigationController?.popToViewController(self, animated: true)

        updateContent()
    }

    @objc public func didFinishEditingContact() {
        Logger.info("\(logTag) \(#function)")

        self.navigationController?.popToViewController(self, animated: true)

        updateContent()
    }
}

//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging
import Reachability
import ContactsUI
import MessageUI

class ContactViewController: OWSViewController, ContactShareViewHelperDelegate {

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

    private let contactsManager: OWSContactsManager

    private var reachability: Reachability?

    private let contactShare: ContactShareViewModel

    private var contactShareViewHelper: ContactShareViewHelper

    private weak var postDismissNavigationController: UINavigationController?

    // MARK: - Initializers

    @available(*, unavailable, message: "use init(call:) constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("Unimplemented")
    }

    required init(contactShare: ContactShareViewModel) {
        contactsManager = Environment.current().contactsManager
        self.contactShare = contactShare
        self.contactShareViewHelper = ContactShareViewHelper(contactsManager: contactsManager)

        super.init(nibName: nil, bundle: nil)

        contactShareViewHelper.delegate = self

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

        // Use "dark" style status bar in this view,
        // But we don't apply the entire default system UI (UIUtil.applyDefaultSystemAppearence) because
        // doing so while pushing onto an existing nav controller who's navbars are hidden corrupts the
        // title label/navbar items elsewhere in the stack.
        CurrentAppContext().setStatusBarStyle(.default)

        guard let navigationController = self.navigationController else {
            owsFail("\(logTag) in \(#function) navigationController was unexpectedly nil")
            return
        }

        // self.navigationController is nil in viewWillDisappear when transition via message/call buttons
        // so we maintain our own reference to restore the navigation bars.
        postDismissNavigationController = navigationController
        navigationController.isNavigationBarHidden = true

        contactsManager.requestSystemContactsOnce(completion: { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.updateMode()
        })
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if self.presentedViewController == nil {
            // No need to do this when we're disappearing due to a modal presentation.
            // We'll eventually return to to this view and need to hide again. But also, there is a visible
            // animation glitch where the navigation bar for this view controller starts to appear while
            // the whole nav stack is about to be obscured by the modal we are presenting.
            guard let postDismissNavigationController = self.postDismissNavigationController else {
                owsFail("\(logTag) in \(#function) postDismissNavigationController was unexpectedly nil")
                return
            }

            postDismissNavigationController.setNavigationBarHidden(false, animated: animated)
        }
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
        SwiftAssertIsOnMainThread(#function)

        return contactShare.systemContactsWithSignalAccountPhoneNumbers(contactsManager)
    }

    private func systemContactsForContact() -> [String] {
        SwiftAssertIsOnMainThread(#function)

        return contactShare.systemContactPhoneNumbers(contactsManager)
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
        let backButton = TappableView(actionBlock: { [weak self] 
            guard let strongSelf = self else { return }
            strongSelf.didPressDismiss()
        })
        backButton.autoSetDimension(.width, toSize: backButtonSize)
        backButton.autoSetDimension(.height, toSize: backButtonSize)
        topView.addSubview(backButton)
        backButton.autoPinEdge(toSuperviewEdge: .top)
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

        let avatarSize: CGFloat = 100
        let avatarView = AvatarImageView()
        avatarView.image = contactShare.getAvatarImage(diameter: avatarSize, contactsManager: contactsManager)
        topView.addSubview(avatarView)
        avatarView.autoPinEdge(toSuperviewEdge: .top, withInset: 20)
        avatarView.autoHCenterInSuperview()
        avatarView.autoSetDimension(.width, toSize: avatarSize)
        avatarView.autoSetDimension(.height, toSize: avatarSize)

        let nameLabel = UILabel()
        nameLabel.text = contactShare.displayName
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
            phoneNumberLabel.text = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber)
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
                                                                  imageName: "contact_view_message",
                                                                  actionBlock: { [weak self] 
                                                                    guard let strongSelf = self else { return }
                                                                    strongSelf.didPressSendMessage()
            }))
            stackView.addArrangedSubview(createCircleActionButton(text: NSLocalizedString("ACTION_AUDIO_CALL",
                                                                                          comment: "Label for 'audio call' button in contact view."),
                                                                  imageName: "contact_view_audio_call",
                                                                  actionBlock: { [weak self] 
                                                                    guard let strongSelf = self else { return }
                                                                    strongSelf.didPressAudioCall()
            }))
            stackView.addArrangedSubview(createCircleActionButton(text: NSLocalizedString("ACTION_VIDEO_CALL",
                                                                                          comment: "Label for 'video call' button in contact view."),
                                                                  imageName: "contact_view_video_call",
                                                                  actionBlock: { [weak self] 
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
                                                     actionBlock: { [weak self] 
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
            let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
            topView.addSubview(activityIndicator)
            activityIndicator.autoPinEdge(.top, to: .bottom, of: lastView, withOffset: 10)
            activityIndicator.autoHCenterInSuperview()
            lastView = activityIndicator
            break
        }

        // Always show "add to contacts" button.
        let addToContactsButton = createLargePillButton(text: NSLocalizedString("CONVERSATION_VIEW_ADD_TO_CONTACTS_OFFER",
                                                                                comment: "Message shown in conversation view that offers to add an unknown user to your phone's contacts."),
                                                        actionBlock: { [weak self] 
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
        SwiftAssertIsOnMainThread(#function)

        var rows = [UIView]()

        // TODO: Not designed yet.
//        if viewMode == .systemContactWithSignal ||
//           viewMode == .systemContactWithoutSignal {
//            addRow(createActionRow(labelText:NSLocalizedString("ACTION_SHARE_CONTACT",
//                                                               comment:"Label for 'share contact' button."),
//                                   action:#selector(didPressShareContact)))
//        }

        if let organizationName = contactShare.name.organizationName?.ows_stripped() {
            if (contactShare.name.hasAnyNamePart() &&
                organizationName.count > 0) {
                rows.append(ContactFieldView.contactFieldView(forOrganizationName: organizationName,
                                                              layoutMargins: UIEdgeInsets(top: 5, left: hMargin, bottom: 5, right: hMargin)))
            }
        }

        for phoneNumber in contactShare.phoneNumbers {
            rows.append(ContactFieldView.contactFieldView(forPhoneNumber: phoneNumber,
                                                          layoutMargins: UIEdgeInsets(top: 5, left: hMargin, bottom: 5, right: hMargin),
                                                          actionBlock: { [weak self] _ in
                                                            guard let strongSelf = self else { return }
                                                            strongSelf.didPressPhoneNumber(phoneNumber: phoneNumber)
            }))
        }

        for email in contactShare.emails {
            rows.append(ContactFieldView.contactFieldView(forEmail: email,
                                                          layoutMargins: UIEdgeInsets(top: 5, left: hMargin, bottom: 5, right: hMargin),
                                                          actionBlock: { [weak self] _ in
                                                            guard let strongSelf = self else { return }
                                                            strongSelf.didPressEmail(email: email)
            }))
        }

        for address in contactShare.addresses {
            rows.append(ContactFieldView.contactFieldView(forAddress: address,
                                                          layoutMargins: UIEdgeInsets(top: 5, left: hMargin, bottom: 5, right: hMargin),
                                                          actionBlock: { [weak self] _ in
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

    // TODO: Use real assets.
    private func createCircleActionButton(text: String, imageName: String, actionBlock : @escaping () -> Void) -> UIView {
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

        guard let image = UIImage(named: imageName) else {
            owsFail("\(logTag) missing image.")
            return button
        }
        let imageView = UIImageView(image: image)
        circleView.addSubview(imageView)
        imageView.autoCenterInSuperview()

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

    func didPressShareContact(sender: UIGestureRecognizer) {
        Logger.info("\(logTag) \(#function)")

        guard sender.state == .recognized else {
            return
        }
        // TODO:
    }

    func didPressSendMessage() {
        Logger.info("\(logTag) \(#function)")

        self.contactShareViewHelper.sendMessage(contactShare: self.contactShare, fromViewController: self)
    }

    func didPressAudioCall() {
        Logger.info("\(logTag) \(#function)")

        self.contactShareViewHelper.audioCall(contactShare: self.contactShare, fromViewController: self)
    }

    func didPressVideoCall() {
        Logger.info("\(logTag) \(#function)")

        self.contactShareViewHelper.videoCall(contactShare: self.contactShare, fromViewController: self)
    }

    func didPressInvite() {
        Logger.info("\(logTag) \(#function)")

        self.contactShareViewHelper.showInviteContact(contactShare: self.contactShare, fromViewController: self)
    }

    func didPressAddToContacts() {
        Logger.info("\(logTag) \(#function)")

        self.contactShareViewHelper.showAddToContacts(contactShare: self.contactShare, fromViewController: self)
    }

    func didPressDismiss() {
        Logger.info("\(self.logTag) \(#function)")

        guard let navigationController = self.navigationController else {
            owsFail("\(logTag) in \(#function) navigationController was unexpectedly nil")
            return
        }

        navigationController.popViewController(animated: true)
    }

    func didPressPhoneNumber(phoneNumber: OWSContactPhoneNumber) {
        Logger.info("\(self.logTag) \(#function)")

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if let e164 = phoneNumber.tryToConvertToE164() {
            if contactShare.systemContactsWithSignalAccountPhoneNumbers(contactsManager).contains(e164) {
                actionSheet.addAction(UIAlertAction(title: NSLocalizedString("ACTION_SEND_MESSAGE",
                                                                             comment: "Label for 'sent message' button in contact view."),
                                                    style: .default) { _ in
                                                        SignalApp.shared().presentConversation(forRecipientId: e164, action: .compose)
                })
                actionSheet.addAction(UIAlertAction(title: NSLocalizedString("ACTION_AUDIO_CALL",
                                                                             comment: "Label for 'audio call' button in contact view."),
                                                    style: .default) { _ in
                                                        SignalApp.shared().presentConversation(forRecipientId: e164, action: .audioCall)
                })
                actionSheet.addAction(UIAlertAction(title: NSLocalizedString("ACTION_VIDEO_CALL",
                                                                             comment: "Label for 'video call' button in contact view."),
                                                    style: .default) { _ in
                                                        SignalApp.shared().presentConversation(forRecipientId: e164, action: .videoCall)
                })
            } else {
                // TODO: We could offer callPhoneNumberWithSystemCall.
            }
        }
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("EDIT_ITEM_COPY_ACTION",
                                                                     comment: "Short name for edit menu item to copy contents of media message."),
                                            style: .default) { _ in
                                                UIPasteboard.general.string = phoneNumber.phoneNumber
        })
        actionSheet.addAction(OWSAlerts.cancelAction)
        present(actionSheet, animated: true)
    }

    func callPhoneNumberWithSystemCall(phoneNumber: OWSContactPhoneNumber) {
        Logger.info("\(self.logTag) \(#function)")

        guard let url = NSURL(string: "tel:\(phoneNumber.phoneNumber)") else {
            owsFail("\(ContactViewController.logTag) could not open phone number.")
            return
        }
        UIApplication.shared.openURL(url as URL)
    }

    func didPressEmail(email: OWSContactEmail) {
        Logger.info("\(self.logTag) \(#function)")

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("CONTACT_VIEW_OPEN_EMAIL_IN_EMAIL_APP",
                                                                     comment: "Label for 'open email in email app' button in contact view."),
                                            style: .default) { [weak self] _ in
                                                self?.openEmailInEmailApp(email: email)
        })
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("EDIT_ITEM_COPY_ACTION",
                                                                     comment: "Short name for edit menu item to copy contents of media message."),
                                            style: .default) { _ in
                                                UIPasteboard.general.string = email.email
        })
        actionSheet.addAction(OWSAlerts.cancelAction)
        present(actionSheet, animated: true)
    }

    func openEmailInEmailApp(email: OWSContactEmail) {
        Logger.info("\(self.logTag) \(#function)")

        guard let url = NSURL(string: "mailto:\(email.email)") else {
            owsFail("\(ContactViewController.logTag) could not open email.")
            return
        }
        UIApplication.shared.openURL(url as URL)
    }

    func didPressAddress(address: OWSContactAddress) {
        Logger.info("\(self.logTag) \(#function)")

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("CONTACT_VIEW_OPEN_ADDRESS_IN_MAPS_APP",
                                                                     comment: "Label for 'open address in maps app' button in contact view."),
                                            style: .default) { [weak self] _ in
                                                self?.openAddressInMaps(address: address)
        })
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("EDIT_ITEM_COPY_ACTION",
                                                                     comment: "Short name for edit menu item to copy contents of media message."),
                                            style: .default) { [weak self] _ in
                                                guard let strongSelf = self else { return }

                                                UIPasteboard.general.string = strongSelf.formatAddressForQuery(address: address)
        })
        actionSheet.addAction(OWSAlerts.cancelAction)
        present(actionSheet, animated: true)
    }

    func openAddressInMaps(address: OWSContactAddress) {
        Logger.info("\(self.logTag) \(#function)")

        let mapAddress = formatAddressForQuery(address: address)
        guard let escapedMapAddress = mapAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            owsFail("\(ContactViewController.logTag) could not open address.")
            return
        }
        // Note that we use "q" (i.e. query) rather than "address" since we can't assume
        // this is a well-formed address.
        guard let url = URL(string: "http://maps.apple.com/?q=\(escapedMapAddress)") else {
            owsFail("\(ContactViewController.logTag) could not open address.")
            return
        }

        UIApplication.shared.openURL(url as URL)
    }

    func formatAddressForQuery(address: OWSContactAddress) -> String {
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
        return addressParts.joined(separator: ", ")
    }

    // MARK: - ContactShareViewHelperDelegate

    public func didCreateOrEditContact() {
        Logger.info("\(logTag) \(#function)")
        updateContent()

        UIUtil.applySignalAppearence()
        self.dismiss(animated: true)
    }
}

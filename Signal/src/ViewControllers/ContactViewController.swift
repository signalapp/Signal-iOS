//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging
import Reachability
import ContactsUI

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
        Logger.info("\(self.logTag) \(#function)")

        guard sender.state == .recognized else {
            return
        }
        actionBlock()
    }
}

// MARK: -

class ContactViewController: OWSViewController, CNContactViewControllerDelegate
//, ContactsViewHelperDelegate
{

    let TAG = "[ContactView]"

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

    override public var canBecomeFirstResponder: Bool {
        return true
    }

    private let contact: OWSContact

//    private var contactsViewHelper : ContactsViewHelper!

    // MARK: - Initializers

    @available(*, unavailable, message: "use init(call:) constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("Unimplemented")
    }

    required init(contact: OWSContact) {
        contactsManager = Environment.current().contactsManager
        self.contact = contact
        self.scrollView = UIScrollView()

        super.init(nibName: nil, bundle: nil)

//        contactsViewHelper = ContactsViewHelper(delegate:self)

        tryToDetermineMode()

        NotificationCenter.default.addObserver(forName: .OWSContactsManagerSignalAccountsDidChange, object: nil, queue: nil) { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.tryToDetermineMode()
        }

        reachability = Reachability.forInternetConnection()

        NotificationCenter.default.addObserver(forName: .reachabilityChanged, object: nil, queue: nil) { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.tryToDetermineMode()
        }
    }

    // MARK: - View Lifecycle

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        UIUtil.applySignalAppearence()

        self.becomeFirstResponder()

        contactsManager.requestSystemContactsOnce(completion: { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.tryToDetermineMode()
        })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIUtil.applySignalAppearence()

        self.becomeFirstResponder()
    }

    private var scrollView: UIScrollView

    override func loadView() {
//        scrollView.dir
//        self.view = scrollView
//        let rootView = UIView()
        super.loadView()
//        self.view.layoutMargins = .zero

//        self.scrollView = scrollView
//        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(scrollView)
        scrollView.layoutMargins = .zero
        scrollView.autoPinWidthToSuperview()
        scrollView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        scrollView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)

        self.view.backgroundColor = UIColor.white

        updateContent()

        hasLoadedView = true
    }

    private func tryToDetermineMode() {
        SwiftAssertIsOnMainThread(#function)

        guard let firstPhoneNumber = contact.phoneNumbers?.first else {
            viewMode = .noPhoneNumber
            return
        }
        if contactsManager.hasSignalAccount(forRecipientId: firstPhoneNumber.phoneNumber) {
            viewMode = .systemContactWithSignal
            return
        }
        if contactsManager.allContactsMap[firstPhoneNumber.phoneNumber] != nil {
            // We can infer that this is _not_ a signal user because
            // all contacts in contactsManager.allContactsMap have
            // already been looked up. 
            viewMode = .systemContactWithoutSignal
            return
        }

        viewMode = .nonSystemContact
    }

    private func tryToDetermineModeRetry() {
        // Try again after a minute.
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 60.0) { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.tryToDetermineMode()
        }
    }

    private func updateContent() {
        SwiftAssertIsOnMainThread(#function)

        let rootView = self.scrollView

        for subview in rootView.subviews {
            subview.removeFromSuperview()
        }

        // TODO: The design calls for no navigation bar, just a back button.
        let topView = UIView.container()
        topView.backgroundColor = UIColor(rgbHex: 0xefeff4)
        topView.preservesSuperviewLayoutMargins = true
        rootView.addSubview(topView)
        topView.autoPinEdge(toSuperviewEdge: .top)
        topView.autoPinEdge(.left, to: .left, of: self.view, withOffset: 0)
        topView.autoPinEdge(.right, to: .right, of: self.view, withOffset: 0)

        // TODO: Use actual avatar.
        let avatarSize = CGFloat(100)
        let avatarView = UIView.container()
        avatarView.backgroundColor = UIColor.ows_materialBlue
        avatarView.layer.cornerRadius = avatarSize * 0.5
        topView.addSubview(avatarView)
        avatarView.autoPin(toTopLayoutGuideOf: self, withInset: 10)
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
        nameLabel.autoPinLeadingToSuperviewMargin()
        nameLabel.autoPinTrailingToSuperviewMargin()

        var lastView: UIView = nameLabel

        if let firstPhoneNumber = contact.phoneNumbers?.first {
            let phoneNumberLabel = UILabel()
            phoneNumberLabel.text = firstPhoneNumber.phoneNumber
            phoneNumberLabel.font = UIFont.ows_dynamicTypeCaption2
            phoneNumberLabel.textColor = UIColor.black
            phoneNumberLabel.lineBreakMode = .byTruncatingTail
            phoneNumberLabel.textAlignment = .center
            topView.addSubview(phoneNumberLabel)
            phoneNumberLabel.autoPinEdge(.top, to: .bottom, of: lastView, withOffset: 5)
            phoneNumberLabel.autoPinLeadingToSuperviewMargin()
            phoneNumberLabel.autoPinTrailingToSuperviewMargin()
            lastView = phoneNumberLabel
        }

        switch viewMode {
        case .systemContactWithSignal:
            // Show actions buttons for system contacts with a Signal account.
            break
        case .systemContactWithoutSignal:
            // Show invite button for system contacts without a Signal account.
            break
        case .nonSystemContact:
            // Show no action buttons for contacts not in user's device contacts.
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

        let bottomView = UIView.container()
        bottomView.backgroundColor = UIColor.white
        bottomView.layoutMargins = .zero
        bottomView.preservesSuperviewLayoutMargins = false
        rootView.addSubview(bottomView)
        bottomView.autoPinEdge(.top, to: .bottom, of: topView, withOffset: 0)
        bottomView.autoPinEdge(toSuperviewEdge: .bottom)
        bottomView.autoPinEdge(.left, to: .left, of: self.view, withOffset: 0)
        bottomView.autoPinEdge(.right, to: .right, of: self.view, withOffset: 0)
        bottomView.setContentHuggingVerticalLow()

        var lastRow: UIView?

        let addSpacerRow = {
            guard let prevRow = lastRow else {
                owsFail("\(self.logTag) missing last row")
                return
            }
            let row = UIView()
            row.backgroundColor = UIColor(rgbHex: 0xdedee1)
            bottomView.addSubview(row)
            row.autoSetDimension(.height, toSize: 1)
            row.autoPinLeadingToSuperviewMargin(withInset: self.hMargin)
            row.autoPinTrailingToSuperviewMargin()
            row.autoPinEdge(.top, to: .bottom, of: prevRow, withOffset: 0)
            lastRow = row
        }

        let addRow: ((UIView) -> Void) = { (row) in
            if lastRow != nil {
                addSpacerRow()
            }
            bottomView.addSubview(row)
            row.autoPinLeadingToSuperviewMargin()
            row.autoPinTrailingToSuperviewMargin()
            if let lastRow = lastRow {
                row.autoPinEdge(.top, to: .bottom, of: lastRow, withOffset: 0)
            } else {
                row.autoPinEdge(toSuperviewEdge: .top, withInset: 0)
            }
            lastRow = row
        }

        if viewMode == .nonSystemContact {
            addRow(createActionRow(labelText: NSLocalizedString("CONVERSATION_SETTINGS_NEW_CONTACT",
                                                               comment: "Label for 'new contact' button in conversation settings view."),
                                   action: #selector(didPressCreateNewContact)))

            addRow(createActionRow(labelText: NSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
                                                               comment: "Label for 'new contact' button in conversation settings view."),
                                   action: #selector(didPressAddToExistingContact)))
        }

        // TODO: Not designed yet.
//        if viewMode == .systemContactWithSignal ||
//           viewMode == .systemContactWithoutSignal {
//            addRow(createActionRow(labelText:NSLocalizedString("ACTION_SHARE_CONTACT",
//                                                               comment:"Label for 'share contact' button."),
//                                   action:#selector(didPressShareContact)))
//        }

        if let phoneNumbers = contact.phoneNumbers {
            for phoneNumber in phoneNumbers {
                // TODO: Try to format the phone number nicely.
                addRow(createNameValueRow(name: phoneNumber.labelString(),
                                          value: phoneNumber.phoneNumber,
                                          actionBlock: {
                                            guard let url = NSURL(string: "tel:\(phoneNumber.phoneNumber)") else {
                                                owsFail("\(ContactViewController.logTag) could not open phone number.")
                                                return
                                            }
                                            UIApplication.shared.openURL(url as URL)
                }))
            }
        }

        if let emails = contact.emails {
            for email in emails {
                addRow(createNameValueRow(name: email.labelString(),
                                          value: email.email,
                                          actionBlock: {
                                            guard let url = NSURL(string: "mailto:\(email.email)") else {
                                                owsFail("\(ContactViewController.logTag) could not open email.")
                                                return
                                            }
                                            UIApplication.shared.openURL(url as URL)
                }))
            }
        }

        // TODO: Should we present addresses here too? How?

        lastRow?.autoPinEdge(toSuperviewEdge: .bottom, withInset: 0)
    }

    private let hMargin = CGFloat(10)

    private func createActionRow(labelText: String, action: Selector) -> UIView {
        let row = UIView()
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

    private func createNameValueRow(name: String, value: String, actionBlock : @escaping () -> Void) -> UIView {
        let row = TappableView(actionBlock: actionBlock)

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = UIFont.ows_dynamicTypeCaption1
        nameLabel.textColor = UIColor.black
        nameLabel.lineBreakMode = .byTruncatingTail
        row.addSubview(nameLabel)
        nameLabel.autoPinTopToSuperviewMargin()
        nameLabel.autoPinLeadingToSuperviewMargin(withInset: hMargin)
        nameLabel.autoPinTrailingToSuperviewMargin(withInset: hMargin)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = UIFont.ows_dynamicTypeCaption1
        valueLabel.textColor = UIColor.ows_materialBlue
        valueLabel.lineBreakMode = .byTruncatingTail
        row.addSubview(valueLabel)
        valueLabel.autoPinEdge(.top, to: .bottom, of: nameLabel, withOffset: 3)
        valueLabel.autoPinBottomToSuperviewMargin()
        valueLabel.autoPinLeadingToSuperviewMargin(withInset: hMargin)
        valueLabel.autoPinTrailingToSuperviewMargin(withInset: hMargin)

        // TODO: Should there be a disclosure icon here?

        return row
    }

//        acceptIncomingButton = createButton(image: #imageLiteral(resourceName: "call-active-wide"),
//                                            action: #selector(didPressAnswerCall))
//        acceptIncomingButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_ACCEPT_INCOMING_CALL_LABEL",
//                                                                    comment: "Accessibility label for accepting incoming calls")

//    func createButton(image: UIImage, action: Selector) -> UIButton {
//        let button = UIButton()
//        button.setImage(image, for: .normal)
//        button.imageEdgeInsets = UIEdgeInsets(top: buttonInset(),
//                                              left: buttonInset(),
//                                              bottom: buttonInset(),
//                                              right: buttonInset())
//        button.addTarget(self, action: action, for: .touchUpInside)
//        button.autoSetDimension(.width, toSize: buttonSize())
//        button.autoSetDimension(.height, toSize: buttonSize())
//        return button
//    }
//
//    // MARK: - Layout
//

//
//    func didPressFlipCamera(sender: UIButton) {
//        // toggle value
//        sender.isSelected = !sender.isSelected
//
//        let useBackCamera = sender.isSelected
//        Logger.info("\(TAG) in \(#function) with useBackCamera: \(useBackCamera)")
//
//        callUIAdapter.setCameraSource(call: call, useBackCamera: useBackCamera)
//    }
//
//    internal func dismissImmediately(completion: (() -> Void)?) {
//        if ContactView.kShowCallViewOnSeparateWindow {
//            OWSWindowManager.shared().endCall(self)
//            completion?()
//        } else {
//            self.dismiss(animated: true, completion: completion)
//        }
//    }

    func didPressCreateNewContact(sender: UIGestureRecognizer) {
        Logger.info("\(self.TAG) \(#function)")

        guard sender.state == .recognized else {
            return
        }
        presentNewContactView()
    }

    func didPressAddToExistingContact(sender: UIGestureRecognizer) {
        Logger.info("\(self.TAG) \(#function)")

        guard sender.state == .recognized else {
            return
        }
        presentSelectAddToExistingContactView()
    }

    func didPressShareContact(sender: UIGestureRecognizer) {
        Logger.info("\(self.TAG) \(#function)")

        guard sender.state == .recognized else {
            return
        }
        // TODO:
    }

    // MARK: - ContactsViewHelperDelegate

//    @objc
//    public func contactsViewHelperDidUpdateContacts() {
//        Logger.info("\(self.TAG) \(#function)")
//
//        // Do nothing
//    }

    // MARK: -

    private func presentNewContactView() {
        guard contactsManager.supportsContactEditing else {
            owsFail("\(self.logTag) Contact editing not supported")
            return
        }
        //        contactsViewHelper.presentContactViewController
        //        let contactsViewHelper = ContactsViewHelper(delegate:self)
        //
        //    TSContactThread *contactThread = (TSContactThread *)self.thread;
        //    [self.contactsViewHelper presentContactViewControllerForRecipientId:contactThread.contactIdentifier
        //    fromViewController:self
        //    editImmediately:YES];

        guard let systemContact = OWSContacts.systemContact(for: contact) else {
            owsFail("\(self.logTag) Could not derive system contact.")
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
            owsFail("\(self.logTag) Contact editing not supported")
            return
        }

        guard let systemContact = OWSContacts.systemContact(for: contact) else {
            owsFail("\(self.logTag) Could not derive system contact.")
            return
        }

        guard contactsManager.isSystemContactsAuthorized else {
            ContactsViewHelper.presentMissingContactAccessAlertController(from: self)
            return
        }

        guard let firstPhoneNumber = contact.phoneNumbers?.first else {
            owsFail("\(self.logTag) Missing phone number.")
            return
        }

        let viewController = OWSAddToContactViewController()
        viewController.configure(withRecipientId: firstPhoneNumber.phoneNumber)
        self.navigationController?.pushViewController(viewController, animated: true)
    }

    // MARK: - CNContactViewControllerDelegate

    @objc public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        Logger.info("\(self.TAG) \(#function)")

        self.navigationController?.popToViewController(self, animated: true)

        updateContent()
    }

    @objc public func didFinishEditingContact() {
        Logger.info("\(self.TAG) \(#function)")

        self.navigationController?.popToViewController(self, animated: true)

        updateContent()
    }
}

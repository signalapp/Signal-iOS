//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging
import Reachability

class ContactViewController: OWSViewController {

    let TAG = "[ContactView]"

    enum ContactViewMode {
        case systemContactWithSignal,
        systemContactWithoutSignal,
        nonSystemContactWithSignal,
        nonSystemContactWithoutSignal,
        noPhoneNumber,
        unknown
    }

    enum ContactLookupMode {
        case notLookingUp,
        lookingUp,
        lookedUpNoAccount,
        lookedUpHasAccount
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

    private var lookupMode = ContactLookupMode.notLookingUp {
        didSet {
            SwiftAssertIsOnMainThread(#function)

            if oldValue != lookupMode && hasLoadedView {
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

    // MARK: - Initializers

    @available(*, unavailable, message: "use init(call:) constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("Unimplemented")
    }

    required init(contact: OWSContact) {
        contactsManager = Environment.current().contactsManager
        self.contact = contact

        super.init(nibName: nil, bundle: nil)

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

        self.becomeFirstResponder()

        contactsManager.requestSystemContactsOnce(completion: { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.tryToDetermineMode()
        })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.becomeFirstResponder()
    }

    override func loadView() {
        super.loadView()
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

        switch lookupMode {
        case .notLookingUp:
            lookupMode = .lookingUp
            viewMode = .unknown
            ContactsUpdater.shared().lookupIdentifiers([firstPhoneNumber.phoneNumber], success: { [weak self] (signalRecipients) in
                guard let strongSelf = self else { return }

                let hasSignalAccount = signalRecipients.filter({ (signalRecipient) -> Bool in
                    return signalRecipient.recipientId() == firstPhoneNumber.phoneNumber
                }).count > 0

                if hasSignalAccount {
                    strongSelf.lookupMode = .lookedUpHasAccount
                    strongSelf.tryToDetermineMode()
                } else {
                    strongSelf.lookupMode = .lookedUpNoAccount
                    strongSelf.tryToDetermineMode()
                }
            }) { [weak self] (error) in
                guard let strongSelf = self else { return }
                Logger.error("\(strongSelf.logTag) error looking up contact: \(error)")
                strongSelf.lookupMode = .notLookingUp
                strongSelf.tryToDetermineModeRetry()
            }
            return
        case .lookingUp:
            viewMode = .unknown
            return
        case .lookedUpNoAccount:
            viewMode = .nonSystemContactWithoutSignal
            return
        case .lookedUpHasAccount:
            viewMode = .nonSystemContactWithSignal
            return
        }
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

        for subview in self.view.subviews {
            subview.removeFromSuperview()
        }

        // TODO: The design calls for no navigation bar, just a back button.
        let topView = UIView.container()
        topView.backgroundColor = UIColor(rgbHex: 0xefeff4)
        topView.preservesSuperviewLayoutMargins = true
        self.view.addSubview(topView)
        topView.autoPinEdge(toSuperviewEdge: .top)
        topView.autoPinWidthToSuperview()

        // TODO: Use actual avatar.
        let avatarSize = CGFloat(100)
        let avatarView = UIView.container()
        avatarView.backgroundColor = UIColor.ows_materialBlue
        avatarView.layer.cornerRadius = avatarSize * 0.5
        topView.addSubview(avatarView)
        avatarView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        avatarView.autoHCenterInSuperview()
        avatarView.autoSetDimension(.width, toSize: avatarSize)
        avatarView.autoSetDimension(.height, toSize: avatarSize)

        let nameLabel = UILabel()
        nameLabel.text = contact.displayName
        nameLabel.font = UIFont.ows_dynamicTypeTitle3
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
            phoneNumberLabel.font = UIFont.ows_dynamicTypeCaption1
            phoneNumberLabel.textColor = UIColor.black
            phoneNumberLabel.lineBreakMode = .byTruncatingTail
            phoneNumberLabel.textAlignment = .center
            topView.addSubview(phoneNumberLabel)
            phoneNumberLabel.autoPinEdge(.top, to: .bottom, of: lastView, withOffset: 10)
            phoneNumberLabel.autoPinLeadingToSuperviewMargin()
            phoneNumberLabel.autoPinTrailingToSuperviewMargin()
            lastView = phoneNumberLabel
        }

        switch viewMode {
        case .systemContactWithSignal:
            break
        case .systemContactWithoutSignal:
            break
        case .nonSystemContactWithSignal:
            break
        case .nonSystemContactWithoutSignal:
            break
        case .noPhoneNumber:
            break
        case .unknown:
            let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
            topView.addSubview(activityIndicator)
            activityIndicator.autoPinEdge(.top, to: .bottom, of: lastView, withOffset: 10)
            activityIndicator.autoHCenterInSuperview()
            lastView = activityIndicator
            break
        }

        lastView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 10)
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
//
}

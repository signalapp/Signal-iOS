//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class PaymentsSendRecipientViewController: OWSViewController {

    private let isOutgoingTransfer: Bool

    let recipientPicker = RecipientPickerViewController()

    public init(isOutgoingTransfer: Bool) {
        self.isOutgoingTransfer = isOutgoingTransfer
    }

    @objc
    public static func presentAsFormSheet(fromViewController: UIViewController,
                                          isOutgoingTransfer: Bool,
                                          paymentRequestModel: TSPaymentRequestModel?) {
        let view = PaymentsSendRecipientViewController(isOutgoingTransfer: isOutgoingTransfer)
        let navigationController = OWSNavigationController(rootViewController: view)
        fromViewController.presentFormSheet(navigationController, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PAYMENTS_SEND_TO_RECIPIENT_TITLE",
                                  comment: "Label for the 'send payment to recipient' view in the payment settings.")

        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)

        recipientPicker.allowsAddByPhoneNumber = false
        recipientPicker.shouldHideLocalRecipient = true
        recipientPicker.allowsSelectingUnregisteredPhoneNumbers = false
        recipientPicker.groupsToShow = .showNoGroups
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)
        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .trailing)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .bottom)

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(didTapDismiss))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        recipientPicker.applyTheme(to: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        recipientPicker.removeTheme(from: self)
    }

    public override func applyTheme() {
        super.applyTheme()

        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)
    }

    @objc
    func didTapDismiss() {
        dismiss(animated: true)
    }

    private func showSendPayment(address: SignalServiceAddress) {
        let recipientHasPaymentsEnabled = databaseStorage.read { transaction in
            Self.paymentsHelper.arePaymentsEnabled(for: address, transaction: transaction)
        }
        guard recipientHasPaymentsEnabled else {
            // TODO: Should we try to fill in this state before showing the error alert?
            ProfileFetcherJob.fetchProfile(address: address, ignoreThrottling: true)

            SendPaymentViewController.showRecipientNotEnabledAlert()
            return
        }

        guard let navigationController = self.navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }
        SendPaymentViewController.present(inNavigationController: navigationController,
                                          delegate: self,
                                          recipientAddress: address,
                                          paymentRequestModel: nil,
                                          isOutgoingTransfer: isOutgoingTransfer,
                                          mode: .fromPaymentSettings)
    }
}

// MARK: -

extension PaymentsSendRecipientViewController: RecipientPickerDelegate {

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        getRecipientState recipient: PickedRecipient
    ) -> RecipientPickerRecipientState {
        // TODO: Nice-to-have: filter out recipients that do not support payments.
        return .canBeSelected
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        didSelectRecipient recipient: PickedRecipient
    ) {
        switch recipient.identifier {
        case .address(let address):
            showSendPayment(address: address)
        case .group:
            owsFailDebug("Invalid recipient.")
            dismiss(animated: true)
        }
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         willRenderRecipient recipient: PickedRecipient) {
        // Do nothing.
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         prepareToSelectRecipient recipient: PickedRecipient) -> AnyPromise {
        owsFailDebug("This method should not called.")
        return AnyPromise(Promise.value(()))
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        didDeselectRecipient recipient: PickedRecipient
    ) {}

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryMessageForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> String? { nil }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         attributedSubtitleForRecipient recipient: PickedRecipient,
                         transaction: SDSAnyReadTransaction) -> NSAttributedString? {
        // TODO: Nice-to-have: filter out recipients that do not support payments.
        switch recipient.identifier {
        case .address(let address):
            guard !address.isLocalAddress else {
                return nil
            }
            if let bioForDisplay = Self.profileManagerImpl.profileBioForDisplay(for: address,
                                                                                transaction: transaction) {
                return NSAttributedString(string: bioForDisplay)
            }
            return nil
        case .group:
            return nil
        }
    }

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {}

    func recipientPickerNewGroupButtonWasPressed() {}

    func recipientPickerCustomHeaderViews() -> [UIView] { return [] }
}

// MARK: -

extension PaymentsSendRecipientViewController: SendPaymentViewDelegate {

    func didSendPayment() {
        dismiss(animated: true, completion: nil)
    }
}

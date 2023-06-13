//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PaymentsSendRecipientViewController: RecipientPickerContainerViewController {

    private let isOutgoingTransfer: Bool

    public init(isOutgoingTransfer: Bool) {
        self.isOutgoingTransfer = isOutgoingTransfer
    }

    public static func presentAsFormSheet(fromViewController: UIViewController,
                                          isOutgoingTransfer: Bool,
                                          paymentRequestModel: TSPaymentRequestModel?) {
        let view = PaymentsSendRecipientViewController(isOutgoingTransfer: isOutgoingTransfer)
        let navigationController = OWSNavigationController(rootViewController: view)
        fromViewController.presentFormSheet(navigationController, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_PAYMENTS_SEND_TO_RECIPIENT_TITLE",
                                  comment: "Label for the 'send payment to recipient' view in the payment settings.")

        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)

        recipientPicker.allowsAddByPhoneNumber = false
        recipientPicker.shouldHideLocalRecipient = true
        recipientPicker.groupsToShow = .noGroups
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)
        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .trailing)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .bottom)

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(didTapDismiss))
    }

    @objc
    private func didTapDismiss() {
        dismiss(animated: true)
    }

    private func showSendPayment(address: SignalServiceAddress) {
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

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryViewForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> ContactCellAccessoryView? { nil }

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

    func didSendPayment(success: Bool) {
        dismiss(animated: true) {
            guard success else {
                // only prompt users to enable payments lock when successful.
                return
            }
            PaymentOnboarding.presentBiometricLockPromptIfNeeded {
                Logger.debug("Payments Lock Request Complete")
            }
        }
    }
}

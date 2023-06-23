//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import MobileCoin
import SignalMessaging
import SignalUI

public class PaymentsTransferOutViewController: OWSTableViewController2 {

    private let transferAmount: TSPaymentAmount?

    // TODO: Should this be a text area?
    private let addressTextfield = UITextField()

    private var addressValue: String? {
        addressTextfield.text?.ows_stripped()
    }

    private var hasValidAddress: Bool {
        guard let addressValue = addressValue else {
            return false
        }
        return !addressValue.isEmpty
    }

    public required init(transferAmount: TSPaymentAmount?) {
        self.transferAmount = transferAmount
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_PAYMENTS_TRANSFER_OUT_TITLE",
                                  comment: "Label for 'transfer currency out' view in the payment settings.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                           target: self,
                                                           action: #selector(didTapDismiss),
                                                           accessibilityIdentifier: "dismiss")

        createViews()

        updateTableContents()

        updateNavbar()
    }

    private func updateNavbar() {
        let rightBarButtonItem = UIBarButtonItem(title: CommonStrings.nextButton,
            style: .plain,
            target: self,
            action: #selector(didTapNext)
        )
        rightBarButtonItem.isEnabled = hasValidAddress
        navigationItem.rightBarButtonItem = rightBarButtonItem
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
        updateNavbar()

        addressTextfield.becomeFirstResponder()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        paymentsSwift.updateCurrentPaymentBalance()
        paymentsCurrencies.updateConversationRatesIfStale()

        addressTextfield.becomeFirstResponder()
    }

    private func createViews() {
        addressTextfield.delegate = self
        addressTextfield.font = .dynamicTypeBodyClamped
        addressTextfield.keyboardAppearance = Theme.keyboardAppearance
        addressTextfield.accessibilityIdentifier = "payments.transfer.out.addressTextfield"
        addressTextfield.addTarget(self, action: #selector(addressDidChange), for: .editingChanged)
    }

    public override func themeDidChange() {
        super.themeDidChange()

        updateTableContents()
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        addressTextfield.textColor = Theme.primaryTextColor
        let placeholder = NSAttributedString(string: OWSLocalizedString("SETTINGS_PAYMENTS_TRANSFER_OUT_PLACEHOLDER",
                                                                       comment: "Placeholder text for the address text field in the 'transfer currency out' settings view."),
                                             attributes: [
                                                .foregroundColor: Theme.secondaryTextAndIconColor
                                             ])
        addressTextfield.attributedPlaceholder = placeholder

        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.footerTitle = OWSLocalizedString("SETTINGS_PAYMENTS_TRANSFER_OUT_FOOTER",
                                                comment: "Footer of the 'transfer currency out' view in the payment settings.")
        let addressTextfield = self.addressTextfield

        let iconView = UIImageView.withTemplateImageName("qr_code", tintColor: Theme.primaryIconColor)
        iconView.autoSetDimensions(to: .square(24))
        iconView.setCompressionResistanceHigh()
        iconView.setContentHuggingHigh()
        iconView.isUserInteractionEnabled = true
        iconView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapScanQR)))

        section.shouldDisableCellSelection = true
        section.add(OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()

            let stackView = UIStackView(arrangedSubviews: [ addressTextfield, iconView ])
            stackView.axis = .horizontal
            stackView.alignment = .center
            stackView.spacing = 8
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            return cell
        },
        actionBlock: nil))
        contents.add(section)

        self.contents = contents
    }

    // MARK: - Events

    @objc
    private func didTapDismiss() {
        dismiss(animated: true, completion: nil)
    }

    @objc
    private func didTapNext() {
        guard let publicAddress = tryToParseAddress() else {
            OWSActionSheets.showActionSheet(title: OWSLocalizedString("SETTINGS_PAYMENTS_TRANSFER_OUT_INVALID_PUBLIC_ADDRESS_TITLE",
                                                                     comment: "Title for error alert indicating that MobileCoin public address is not valid."),
                                            message: OWSLocalizedString("SETTINGS_PAYMENTS_TRANSFER_OUT_INVALID_PUBLIC_ADDRESS",
                                                                       comment: "Error indicating that MobileCoin public address is not valid."))
            return
        }
        let recipientAddressBase58 = PaymentsImpl.formatAsBase58(publicAddress: publicAddress)
        guard let localWalletAddressBase58 = payments.walletAddressBase58(),
              localWalletAddressBase58 != recipientAddressBase58 else {
            OWSActionSheets.showActionSheet(title: OWSLocalizedString("SETTINGS_PAYMENTS_TRANSFER_OUT_INVALID_PUBLIC_ADDRESS_TITLE",
                                                                     comment: "Title for error alert indicating that MobileCoin public address is not valid."),
                                            message: OWSLocalizedString("SETTINGS_PAYMENTS_TRANSFER_OUT_CANNOT_SEND_TO_SELF",
                                                                       comment: "Error indicating that it is not valid to send yourself a payment."))
            return
        }

        let recipient: SendPaymentRecipientImpl = .publicAddress(publicAddress: publicAddress)
        let view = SendPaymentViewController(recipient: recipient,
                                             paymentRequestModel: nil,
                                             initialPaymentAmount: transferAmount,
                                             isOutgoingTransfer: true,
                                             mode: .fromTransferOutFlow)
        view.delegate = self
        navigationController?.pushViewController(view, animated: true)
    }

    private func tryToParseAddress() -> MobileCoin.PublicAddress? {
        guard let text = addressTextfield.text?.ows_stripped() else {
            return nil
        }
        if let publicAddress = PaymentsImpl.parse(publicAddressBase58: text) {
            return publicAddress
        }
        owsFailDebug("Could not parse value.")
        return nil
    }

    @objc
    private func addressDidChange() {
        updateNavbar()
    }

    @objc
    private func didTapScanQR() {
        let view = PaymentsQRScanViewController(delegate: self)
        navigationController?.pushViewController(view, animated: true)
    }
}

// MARK: -

extension PaymentsTransferOutViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return true
    }
}

// MARK: -

extension PaymentsTransferOutViewController: SendPaymentViewDelegate {
    public func didSendPayment(success: Bool) {
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

// MARK: -

extension PaymentsTransferOutViewController: PaymentsQRScanDelegate {
    public func didScanPaymentAddressQRCode(publicAddressBase58: String) {
        addressTextfield.text = publicAddressBase58
        updateNavbar()
    }
}

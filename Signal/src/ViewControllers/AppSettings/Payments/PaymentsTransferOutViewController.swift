//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MobileCoin
import SignalServiceKit
import SignalUI

class PaymentsTransferOutViewController: OWSTableViewController2, UITextFieldDelegate,
    SendPaymentViewDelegate, PaymentsQRScanDelegate
{
    private let transferAmount: TSPaymentAmount?

    private lazy var addressTextfield: UITextField = {
        let textField = UITextField()
        textField.delegate = self
        textField.textColor = .Signal.label
        textField.tintColor = .Signal.label
        textField.font = .dynamicTypeBodyClamped
        textField.accessibilityIdentifier = "payments.transfer.out.addressTextfield"
        textField.addTarget(self, action: #selector(addressDidChange), for: .editingChanged)
        textField.placeholder = OWSLocalizedString(
            "SETTINGS_PAYMENTS_TRANSFER_OUT_PLACEHOLDER",
            comment: "Placeholder text for the address text field in the 'transfer currency out' settings view.",
        )
        return textField
    }()

    private var addressValue: String? {
        addressTextfield.text?.ows_stripped()
    }

    private var hasValidAddress: Bool {
        guard let addressValue else {
            return false
        }
        return !addressValue.isEmpty
    }

    init(transferAmount: TSPaymentAmount?) {
        self.transferAmount = transferAmount
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_TRANSFER_OUT_TITLE",
            comment: "Label for 'transfer currency out' view in the payment settings.",
        )

        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.didTapDismiss()
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: CommonStrings.nextButton,
            primaryAction: UIAction { [weak self] _ in
                self?.didTapNext()
            },
        )

        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateNavbar()
        addressTextfield.becomeFirstResponder()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        SUIEnvironment.shared.paymentsSwiftRef.updateCurrentPaymentBalance()
        SSKEnvironment.shared.paymentsCurrenciesRef.updateConversionRates()

        addressTextfield.becomeFirstResponder()
    }

    private func updateNavbar() {
        navigationItem.rightBarButtonItem?.isEnabled = hasValidAddress
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.footerTitle = OWSLocalizedString(
            "SETTINGS_PAYMENTS_TRANSFER_OUT_FOOTER",
            comment: "Footer of the 'transfer currency out' view in the payment settings.",
        )
        let addressTextfield = self.addressTextfield

        let qrCodeButton = UIButton(
            configuration: .plain(),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapScanQR()
            },
        )
        qrCodeButton.configuration?.image = UIImage(named: "qr_code")
        qrCodeButton.configuration?.contentInsets = .init(margin: 4)

        section.shouldDisableCellSelection = true
        section.add(OWSTableItem(
            customCellBlock: {
                let cell = OWSTableItem.newCell()

                let stackView = UIStackView(arrangedSubviews: [addressTextfield, qrCodeButton])
                stackView.axis = .horizontal
                stackView.alignment = .center
                stackView.spacing = 8
                cell.contentView.addSubview(stackView)
                stackView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    stackView.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
                    stackView.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                    stackView.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                    stackView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
                ])

                return cell
            },
        ))
        contents.add(section)

        self.contents = contents
    }

    // MARK: - Events

    private func didTapDismiss() {
        dismiss(animated: true, completion: nil)
    }

    private func didTapNext() {
        guard let publicAddress = tryToParseAddress() else {
            OWSActionSheets.showActionSheet(
                title: OWSLocalizedString(
                    "SETTINGS_PAYMENTS_TRANSFER_OUT_INVALID_PUBLIC_ADDRESS_TITLE",
                    comment: "Title for error alert indicating that MobileCoin public address is not valid.",
                ),
                message: OWSLocalizedString(
                    "SETTINGS_PAYMENTS_TRANSFER_OUT_INVALID_PUBLIC_ADDRESS",
                    comment: "Error indicating that MobileCoin public address is not valid.",
                ),
            )
            return
        }

        let recipientAddressBase58 = PaymentsImpl.formatAsBase58(publicAddress: publicAddress)
        guard
            let localWalletAddressBase58 = SUIEnvironment.shared.paymentsRef.walletAddressBase58(),
            localWalletAddressBase58 != recipientAddressBase58
        else {
            OWSActionSheets.showActionSheet(
                title: OWSLocalizedString(
                    "SETTINGS_PAYMENTS_TRANSFER_OUT_INVALID_PUBLIC_ADDRESS_TITLE",
                    comment: "Title for error alert indicating that MobileCoin public address is not valid.",
                ),
                message: OWSLocalizedString(
                    "SETTINGS_PAYMENTS_TRANSFER_OUT_CANNOT_SEND_TO_SELF",
                    comment: "Error indicating that it is not valid to send yourself a payment.",
                ),
            )
            return
        }

        let recipient: SendPaymentRecipientImpl = .publicAddress(publicAddress: publicAddress)
        let view = SendPaymentViewController(
            recipient: recipient,
            initialPaymentAmount: transferAmount,
            isOutgoingTransfer: true,
            mode: .fromTransferOutFlow,
        )
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
        return nil
    }

    @objc
    private func addressDidChange() {
        updateNavbar()
    }

    private func didTapScanQR() {
        let view = PaymentsQRScanViewController(delegate: self)
        navigationController?.pushViewController(view, animated: true)
    }

    // MARK: - UITextFieldDelegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return true
    }

    // MARK: - SendPaymentViewDelegate

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

    // MARK: - PaymentsQRScanDelegate

    func didScanPaymentAddressQRCode(publicAddressBase58: String) {
        addressTextfield.text = publicAddressBase58
        updateNavbar()
    }
}

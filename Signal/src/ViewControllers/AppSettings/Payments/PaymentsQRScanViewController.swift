//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

@MainActor
protocol PaymentsQRScanDelegate: AnyObject {
    func didScanPaymentAddressQRCode(publicAddressBase58: String)
}

// MARK: -

class PaymentsQRScanViewController: OWSViewController, QRCodeScanDelegate {

    private weak var delegate: PaymentsQRScanDelegate?

    private let qrCodeScanViewController = QRCodeScanViewController(appearance: .framed)

    init(delegate: PaymentsQRScanDelegate) {
        self.delegate = delegate
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_SCAN_QR_TITLE",
            comment: "Label for 'scan payment address QR code' view in the payment settings.",
        )

        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.didTapCancel()
        }

        view.backgroundColor = .Signal.background

        qrCodeScanViewController.delegate = self
        addChild(qrCodeScanViewController)
        let qrView = qrCodeScanViewController.view!
        view.addSubview(qrView)

        let footer = UIView()
        footer.backgroundColor = .Signal.secondaryBackground
        footer.preservesSuperviewLayoutMargins = true
        view.addSubview(footer)

        let instructionsLabel = UILabel()
        instructionsLabel.text = OWSLocalizedString(
            "SETTINGS_PAYMENTS_SCAN_QR_INSTRUCTIONS",
            comment: "Instructions in the 'scan payment address QR code' view in the payment settings.",
        )
        instructionsLabel.font = .dynamicTypeBody
        instructionsLabel.textColor = .Signal.label
        instructionsLabel.textAlignment = .center
        instructionsLabel.numberOfLines = 0
        instructionsLabel.lineBreakMode = .byWordWrapping
        footer.addSubview(instructionsLabel)

        qrView.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        instructionsLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            qrView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            qrView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            qrView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            footer.topAnchor.constraint(equalTo: qrView.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            instructionsLabel.topAnchor.constraint(equalTo: footer.topAnchor, constant: 16),
            instructionsLabel.leadingAnchor.constraint(equalTo: footer.layoutMarginsGuide.leadingAnchor),
            instructionsLabel.trailingAnchor.constraint(equalTo: footer.layoutMarginsGuide.trailingAnchor),
            instructionsLabel.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    // MARK: - Events

    private func didTapCancel() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - QRCodeScanDelegate

    func qrCodeScanViewDismiss(_ qrCodeScanViewController: QRCodeScanViewController) {
        navigationController?.popViewController(animated: true)
    }

    func qrCodeScanViewScanned(
        qrCodeData: Data?,
        qrCodeString: String?,
    ) -> QRCodeScanOutcome {
        // Prefer qrCodeString to qrCodeData.  The only valid payload
        // is a address encoded as either b58 and/or URL.
        // Either way, the payload will be a utf8 string that iOS
        // can decode.  iOS supports many more QR code modes and
        // configurations than QRCodePayload, so the qrCodeString is
        // more reliable than qrCodeData.
        if let qrCodeString {
            if nil != PaymentsImpl.parse(publicAddressBase58: qrCodeString) {
                delegate?.didScanPaymentAddressQRCode(publicAddressBase58: qrCodeString)
                navigationController?.popViewController(animated: true)
                return .stopScanning
            } else if
                let publicAddressUrl = URL(string: qrCodeString),
                let publicAddress = PaymentsImpl.parseAsPublicAddress(url: publicAddressUrl)
            {
                let publicAddressBase58 = PaymentsImpl.formatAsBase58(publicAddress: publicAddress)
                delegate?.didScanPaymentAddressQRCode(publicAddressBase58: publicAddressBase58)
                navigationController?.popViewController(animated: true)
                return .stopScanning
            }
        }
        OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
            "SETTINGS_PAYMENTS_SCAN_QR_INVALID_PUBLIC_ADDRESS",
            comment: "Error indicating that a QR code does not contain a valid MobileCoin public address.",
        ))
        return .continueScanning
    }
}

//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PaymentsQRScanDelegate: AnyObject {
    func didScanPaymentAddressQRCode(publicAddressBase58: String)
}

// MARK: -

public class PaymentsQRScanViewController: OWSViewController {

    private weak var delegate: PaymentsQRScanDelegate?

    private let qrCodeScanViewController = QRCodeScanViewController(appearance: .normal)

    public required init(delegate: PaymentsQRScanDelegate) {
        self.delegate = delegate
        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PAYMENTS_SCAN_QR_TITLE",
                                  comment: "Label for 'scan payment address QR code' view in the payment settings.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                           target: self,
                                                           action: #selector(didTapCancel),
                                                           accessibilityIdentifier: "cancel")

        createViews()
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    private func createViews() {
        view.backgroundColor = .ows_black

        qrCodeScanViewController.delegate = self
        addChild(qrCodeScanViewController)
        let qrView = qrCodeScanViewController.view!
        view.addSubview(qrView)
        qrView.autoPinWidthToSuperview()
        qrView.autoPin(toTopLayoutGuideOf: self, withInset: 0)

        let footer = UIView.container()
        footer.backgroundColor = UIColor(white: 0.25, alpha: 1.0)
        view.addSubview(footer)
        footer.autoPinWidthToSuperview()
        footer.autoPinEdge(toSuperviewEdge: .bottom)
        footer.autoPinEdge(.top, to: .bottom, of: qrView)

        let instructionsLabel = UILabel()
        instructionsLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_SCAN_QR_INSTRUCTIONS",
                                                        comment: "Instructions in the 'scan payment address QR code' view in the payment settings.")
        instructionsLabel.font = .ows_dynamicTypeBody
        instructionsLabel.textColor = .ows_white
        instructionsLabel.textAlignment = .center
        instructionsLabel.numberOfLines = 0
        instructionsLabel.lineBreakMode = .byWordWrapping
        footer.addSubview(instructionsLabel)
        instructionsLabel.autoPinWidthToSuperview(withMargin: 20)
        instructionsLabel.autoPin(toBottomLayoutGuideOf: self, withInset: 16)
        instructionsLabel.autoPinEdge(toSuperviewEdge: .top, withInset: 16)
    }

    // MARK: - Events

    @objc
    func didTapCancel() {
        navigationController?.popViewController(animated: true)
    }
}

// MARK: -

extension PaymentsQRScanViewController: QRCodeScanDelegate {

    public func qrCodeScanViewDismiss(_ qrCodeScanViewController: QRCodeScanViewController) {
        AssertIsOnMainThread()

        navigationController?.popViewController(animated: true)
    }

    public func qrCodeScanViewScanned(_ qrCodeScanViewController: QRCodeScanViewController,
                                      qrCodeData: Data?,
                                      qrCodeString: String?) -> QRCodeScanOutcome {
        AssertIsOnMainThread()

        // Prefer qrCodeString to qrCodeData.  The only valid payload
        // is a public address encoded as either b58 and/or URL.
        // Either way, the payload will be a utf8 string that iOS
        // can decode.  iOS supports many more QR code modes and
        // configurations than QRCodePayload, so the qrCodeString is
        // more reliable than qrCodeData.
        if let qrCodeString = qrCodeString {
            if nil != PaymentsImpl.parse(publicAddressBase58: qrCodeString) {
                delegate?.didScanPaymentAddressQRCode(publicAddressBase58: qrCodeString)
                navigationController?.popViewController(animated: true)
                return .stopScanning
            } else if let publicAddressUrl = URL(string: qrCodeString),
                      let publicAddress = PaymentsImpl.parseAsPublicAddress(url: publicAddressUrl) {
                let publicAddressBase58 = PaymentsImpl.formatAsBase58(publicAddress: publicAddress)
                delegate?.didScanPaymentAddressQRCode(publicAddressBase58: publicAddressBase58)
                navigationController?.popViewController(animated: true)
                return .stopScanning
            }
        }
        OWSActionSheets.showErrorAlert(message: NSLocalizedString("SETTINGS_PAYMENTS_SCAN_QR_INVALID_PUBLIC_ADDRESS",
                                                                  comment: "Error indicating that a QR code does not contain a valid MobileCoin public address."))
        return .continueScanning
   }
}

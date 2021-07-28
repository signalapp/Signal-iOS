//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public protocol PaymentsQRScanDelegate: AnyObject {
    func didScanPaymentAddressQRCode(publicAddressBase58: String)
}

// MARK: -

public class PaymentsQRScanViewController: OWSViewController {

    private weak var delegate: PaymentsQRScanDelegate?

    private let qrScanningController = OWSQRCodeScanningViewController()

    public required init(delegate: PaymentsQRScanDelegate) {
        self.delegate = delegate
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

        self.ows_askForCameraPermissions { [weak self] granted in
            guard let self = self else {
                return
            }
            if granted {
            // Camera stops capturing when "sharing" while in capture mode.
            // Also, it's less obvious whats being "shared" at this point,
            // so just disable sharing when in capture mode.

                Logger.info("Showing Scanner")
                self.qrScanningController.startCapture()
            } else {
                self.didTapCancel()
            }
        }
    }

    private func createViews() {
        view.backgroundColor = .ows_black

        qrScanningController.scanDelegate = self
        let qrView = qrScanningController.view!
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

extension PaymentsQRScanViewController: OWSQRScannerDelegate {
    public func controller(_ controller: OWSQRCodeScanningViewController, didDetectQRCodeWith data: Data) {
        if let dataString = String(data: data, encoding: .utf8) {
            if nil != PaymentsImpl.parse(publicAddressBase58: dataString) {
                delegate?.didScanPaymentAddressQRCode(publicAddressBase58: dataString)
                navigationController?.popViewController(animated: true)
                return
            } else if let publicAddressUrl = URL(string: dataString),
                      let publicAddress = PaymentsImpl.parseAsPublicAddress(url: publicAddressUrl) {
                let publicAddressBase58 = PaymentsImpl.formatAsBase58(publicAddress: publicAddress)
                delegate?.didScanPaymentAddressQRCode(publicAddressBase58: publicAddressBase58)
                navigationController?.popViewController(animated: true)
                return
            }
        }
        OWSActionSheets.showErrorAlert(message: NSLocalizedString("SETTINGS_PAYMENTS_SCAN_QR_INVALID_PUBLIC_ADDRESS",
                                                                  comment: "Error indicating that a QR code does not contain a valid MobileCoin public address."))
    }

    public func controller(_ controller: OWSQRCodeScanningViewController, didDetectQRCodeWith string: String) {
        guard let publicAddressUrl = URL(string: string),
              let publicAddress = PaymentsImpl.parseAsPublicAddress(url: publicAddressUrl) else {
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("SETTINGS_PAYMENTS_SCAN_QR_INVALID_PUBLIC_ADDRESS_URL",
                                                                      comment: "Error indicating that a QR code does not contain a valid MobileCoin public address URL."))
            return
        }
        let publicAddressBase58 = PaymentsImpl.formatAsBase58(publicAddress: publicAddress)
        delegate?.didScanPaymentAddressQRCode(publicAddressBase58: publicAddressBase58)
        navigationController?.popViewController(animated: true)
    }
}


final class ScanQRCodeWrapperVC : UIViewController {
    var delegate: (UIViewController & OWSQRScannerDelegate)? = nil
    private let scanQRCodeVC = OWSQRCodeScanningViewController()
    
    // MARK: Settings
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .portrait }
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Background color
        view.backgroundColor = Theme.backgroundColor
        // Scan QR code VC
        scanQRCodeVC.scanDelegate = delegate
        let scanQRCodeVCView = scanQRCodeVC.view!
        view.addSubview(scanQRCodeVCView)
        scanQRCodeVCView.pin(.leading, to: .leading, of: view)
        scanQRCodeVCView.pin(.trailing, to: .trailing, of: view)
        scanQRCodeVCView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        scanQRCodeVCView.autoPinToSquareAspectRatio()
        // Bottom view
        let bottomView = UIView()
        view.addSubview(bottomView)
        bottomView.pin(.top, to: .bottom, of: scanQRCodeVCView)
        bottomView.pin(.leading, to: .leading, of: view)
        bottomView.pin(.trailing, to: .trailing, of: view)
        bottomView.pin(.bottom, to: .bottom, of: view)
        // Explanation label
        let explanationLabel = UILabel()
        explanationLabel.text = NSLocalizedString("Scan the QR code of the person you'd like to securely message. They can find their QR code by going into Loki Messenger's in-app settings and clicking \"Show QR Code\".", comment: "")
        explanationLabel.textColor = Theme.primaryColor
        explanationLabel.font = .ows_dynamicTypeSubheadlineClamped
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.textAlignment = .center
        bottomView.addSubview(explanationLabel)
        explanationLabel.autoPinWidthToSuperview(withMargin: 32)
        explanationLabel.autoPinHeightToSuperview(withMargin: 32)
        // Title
        title = NSLocalizedString("Scan QR Code", comment: "")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIDevice.current.ows_setOrientation(.portrait)
        DispatchQueue.main.async { [weak self] in
            self?.scanQRCodeVC.startCapture()
        }
    }
}

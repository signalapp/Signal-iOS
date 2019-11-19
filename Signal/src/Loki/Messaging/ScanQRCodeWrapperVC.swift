
final class ScanQRCodeWrapperVC : UIViewController {
    var delegate: (UIViewController & OWSQRScannerDelegate)? = nil
    var isPresentedModally = false
    private let message: String
    private let scanQRCodeVC = OWSQRCodeScanningViewController()
    
    // MARK: Settings
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .portrait }
    
    // MARK: Lifecycle
    init(message: String) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(title:) instead.")
    }
    
    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(title:) instead.")
    }
    
    override func viewDidLoad() {
        // Navigation bar
        if isPresentedModally {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(objc_dismiss))
        }
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
        explanationLabel.text = message
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
    
    // MARK: Interaction
    @objc private func objc_dismiss() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
}

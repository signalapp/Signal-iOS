
final class QRCodeVC : BaseVC, UIPageViewControllerDataSource, UIPageViewControllerDelegate, OWSQRScannerDelegate {
    private let pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    private var pages: [UIViewController] = []
    private var targetVCIndex: Int?
    private var tabBarTopConstraint: NSLayoutConstraint!
    
    // MARK: Components
    private lazy var tabBar: TabBar = {
        let tabs = [
            TabBar.Tab(title: NSLocalizedString("View My QR Code", comment: "")) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[0] ], direction: .forward, animated: false, completion: nil)
            },
            TabBar.Tab(title: NSLocalizedString("Scan QR Code", comment: "")) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[1] ], direction: .forward, animated: false, completion: nil)
            }
        ]
        return TabBar(tabs: tabs)
    }()
    
    private lazy var viewMyQRCodeVC: ViewMyQRCodeVC = {
        let result = ViewMyQRCodeVC()
        result.qrCodeVC = self
        return result
    }()
    
    private lazy var scanQRCodePlaceholderVC: ScanQRCodePlaceholderVC = {
        let result = ScanQRCodePlaceholderVC()
        result.qrCodeVC = self
        return result
    }()
    
    private lazy var scanQRCodeWrapperVC: ScanQRCodeWrapperVC = {
        let message = NSLocalizedString("Scan someone's QR code to start a conversation with them", comment: "")
        let result = ScanQRCodeWrapperVC(message: message)
        result.delegate = self
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle(NSLocalizedString("QR Code", comment: ""))
        let navigationBar = navigationController!.navigationBar
        // Set up page VC
        let hasCameraAccess = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        pages = [ viewMyQRCodeVC, (hasCameraAccess ? scanQRCodeWrapperVC : scanQRCodePlaceholderVC) ]
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.setViewControllers([ viewMyQRCodeVC ], direction: .forward, animated: false, completion: nil)
        // Set up tab bar
        view.addSubview(tabBar)
        tabBar.pin(.leading, to: .leading, of: view)
        tabBarTopConstraint = tabBar.autoPinEdge(toSuperviewSafeArea: .top)
        view.pin(.trailing, to: .trailing, of: tabBar)
        // Set up page VC constraints
        let pageVCView = pageVC.view!
        view.addSubview(pageVCView)
        pageVCView.pin(.leading, to: .leading, of: view)
        pageVCView.pin(.top, to: .bottom, of: tabBar)
        view.pin(.trailing, to: .trailing, of: pageVCView)
        view.pin(.bottom, to: .bottom, of: pageVCView)
        let screen = UIScreen.main.bounds
        pageVCView.set(.width, to: screen.width)
        let height: CGFloat
        if #available(iOS 13, *) {
            height = navigationController!.view.bounds.height - navigationBar.height() - Values.tabBarHeight
        } else {
            let statusBarHeight = UIApplication.shared.statusBarFrame.height
            height = navigationController!.view.bounds.height - navigationBar.height() - Values.tabBarHeight - statusBarHeight
        }
        pageVCView.set(.height, to: height)
        viewMyQRCodeVC.constrainHeight(to: height)
        scanQRCodePlaceholderVC.constrainHeight(to: height)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tabBarTopConstraint.constant = navigationController!.navigationBar.height()
    }
    
    // MARK: General
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController), index != 0 else { return nil }
        return pages[index - 1]
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController), index != (pages.count - 1) else { return nil }
        return pages[index + 1]
    }
    
    fileprivate func handleCameraAccessGranted() {
        pages[1] = scanQRCodeWrapperVC
        pageVC.setViewControllers([ scanQRCodeWrapperVC ], direction: .forward, animated: false, completion: nil)
    }
    
    // MARK: Updating
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        guard let targetVC = pendingViewControllers.first, let index = pages.firstIndex(of: targetVC) else { return }
        targetVCIndex = index
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating isFinished: Bool, previousViewControllers: [UIViewController], transitionCompleted isCompleted: Bool) {
        guard isCompleted, let index = targetVCIndex else { return }
        tabBar.selectTab(at: index)
    }
    
    // MARK: Interaction
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
    
    func controller(_ controller: OWSQRCodeScanningViewController, didDetectQRCodeWith string: String) {
        let hexEncodedPublicKey = string
        startNewPrivateChatIfPossible(with: hexEncodedPublicKey)
    }
    
    fileprivate func startNewPrivateChatIfPossible(with hexEncodedPublicKey: String) {
        if !ECKeyPair.isValidHexEncodedPublicKey(candidate: hexEncodedPublicKey) {
            let alert = UIAlertController(title: NSLocalizedString("Invalid Session ID", comment: ""), message: NSLocalizedString("Please check the Session ID and try again.", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            presentAlert(alert)
        } else {
            let thread = TSContactThread.getOrCreateThread(contactId: hexEncodedPublicKey)
            presentingViewController?.dismiss(animated: true, completion: nil)
            SignalApp.shared().presentConversation(for: thread, action: .compose, animated: false)
        }
    }
}

private final class ViewMyQRCodeVC : UIViewController {
    weak var qrCodeVC: QRCodeVC!
    private var bottomConstraint: NSLayoutConstraint!
    
    private lazy var userHexEncodedPublicKey: String = {
        if let masterHexEncodedPublicKey = UserDefaults.standard[.masterHexEncodedPublicKey] {
            return masterHexEncodedPublicKey
        } else {
            return getUserHexEncodedPublicKey()
        }
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Remove background color
        view.backgroundColor = .clear
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: isIPhone5OrSmaller ? CGFloat(40) : Values.massiveFontSize)
        titleLabel.text = NSLocalizedString("Scan Me", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byWordWrapping
        // Set up QR code image view
        let qrCodeImageView = UIImageView()
        let qrCode = QRCode.generate(for: userHexEncodedPublicKey, hasBackground: true)
        qrCodeImageView.image = qrCode
        qrCodeImageView.contentMode = .scaleAspectFit
        qrCodeImageView.set(.height, to: isIPhone5OrSmaller ? 180 : 240)
        qrCodeImageView.set(.width, to: isIPhone5OrSmaller ? 180 : 240)
        // Set up QR code image view container
        let qrCodeImageViewContainer = UIView()
        qrCodeImageViewContainer.addSubview(qrCodeImageView)
        qrCodeImageView.center(.horizontal, in: qrCodeImageViewContainer)
        qrCodeImageView.pin(.top, to: .top, of: qrCodeImageViewContainer)
        qrCodeImageView.pin(.bottom, to: .bottom, of: qrCodeImageViewContainer)
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.mediumFontSize)
//        let text = NSLocalizedString("This is your QR code. Other users can scan it to start a session with you.", comment: "")
//        let attributedText = NSMutableAttributedString(string: text)
//        attributedText.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: Values.mediumFontSize), range: (text as NSString).range(of: "your unique public QR code"))
//        explanationLabel.attributedText = attributedText
        explanationLabel.text = NSLocalizedString("This is your QR code. Other users can scan it to start a session with you.", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up share button
        let shareButton = Button(style: .regular, size: .large)
        shareButton.setTitle(NSLocalizedString("Share", comment: ""), for: UIControl.State.normal)
        shareButton.addTarget(self, action: #selector(shareQRCode), for: UIControl.Event.touchUpInside)
        // Set up share button container
        let shareButtonContainer = UIView()
        shareButtonContainer.addSubview(shareButton)
        shareButton.pin(.leading, to: .leading, of: shareButtonContainer, withInset: 80)
        shareButton.pin(.top, to: .top, of: shareButtonContainer)
        shareButtonContainer.pin(.trailing, to: .trailing, of: shareButton, withInset: 80)
        shareButtonContainer.pin(.bottom, to: .bottom, of: shareButton)
        // Set up stack view
        let stackView = UIStackView(arrangedSubviews: [ titleLabel, qrCodeImageViewContainer, explanationLabel, shareButtonContainer, UIView.vStretchingSpacer() ])
        stackView.axis = .vertical
        stackView.spacing = isIPhone5OrSmaller ? Values.mediumSpacing : Values.largeSpacing
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: Values.largeSpacing, left: Values.largeSpacing, bottom: Values.largeSpacing, right: Values.largeSpacing)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: view)
        stackView.pin(.top, to: .top, of: view)
        view.pin(.trailing, to: .trailing, of: stackView)
        bottomConstraint = view.pin(.bottom, to: .bottom, of: stackView)
        // Set up width constraint
        view.set(.width, to: UIScreen.main.bounds.width)
    }
    
    // MARK: General
    func constrainHeight(to height: CGFloat) {
        view.set(.height, to: height)
    }
    
    // MARK: Interaction
    @objc private func shareQRCode() {
        let qrCode = QRCode.generate(for: userHexEncodedPublicKey, hasBackground: true)
        let shareVC = UIActivityViewController(activityItems: [ qrCode ], applicationActivities: nil)
        qrCodeVC.navigationController!.present(shareVC, animated: true, completion: nil)
    }
}

private final class ScanQRCodePlaceholderVC : UIViewController {
    weak var qrCodeVC: QRCodeVC!
    
    override func viewDidLoad() {
        // Remove background color
        view.backgroundColor = .clear
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = NSLocalizedString("Session needs camera access to scan QR codes", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up call to action button
        let callToActionButton = UIButton()
        callToActionButton.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        callToActionButton.setTitleColor(Colors.accent, for: UIControl.State.normal)
        callToActionButton.setTitle(NSLocalizedString("Enable Camera Access", comment: ""), for: UIControl.State.normal)
        callToActionButton.addTarget(self, action: #selector(requestCameraAccess), for: UIControl.Event.touchUpInside)
        // Set up stack view
        let stackView = UIStackView(arrangedSubviews: [ explanationLabel, callToActionButton ])
        stackView.axis = .vertical
        stackView.spacing = Values.mediumSpacing
        stackView.alignment = .center
        // Set up constraints
        view.set(.width, to: UIScreen.main.bounds.width)
        view.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: view, withInset: Values.massiveSpacing)
        view.pin(.trailing, to: .trailing, of: stackView, withInset: Values.massiveSpacing)
        let verticalCenteringConstraint = stackView.center(.vertical, in: view)
        verticalCenteringConstraint.constant = -16 // Makes things appear centered visually
    }
    
    func constrainHeight(to height: CGFloat) {
        view.set(.height, to: height)
    }
    
    @objc private func requestCameraAccess() {
        ows_ask(forCameraPermissions: { [weak self] hasCameraAccess in
            if hasCameraAccess {
                self?.qrCodeVC.handleCameraAccessGranted()
            } else {
                // Do nothing
            }
        })
    }
}


final class NewPrivateChatVC : BaseVC, UIPageViewControllerDataSource, UIPageViewControllerDelegate, OWSQRScannerDelegate {
    private let pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    private var pages: [UIViewController] = []
    private var targetVCIndex: Int?
    
    // MARK: Components
    private lazy var tabBar: TabBar = {
        let tabs = [
            TabBar.Tab(title: NSLocalizedString("vc_create_private_chat_enter_session_id_tab_title", comment: "")) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[0] ], direction: .forward, animated: false, completion: nil)
            },
            TabBar.Tab(title: NSLocalizedString("vc_create_private_chat_scan_qr_code_tab_title", comment: "")) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[1] ], direction: .forward, animated: false, completion: nil)
            }
        ]
        return TabBar(tabs: tabs)
    }()
    
    private lazy var enterPublicKeyVC: EnterPublicKeyVC = {
        let result = EnterPublicKeyVC()
        result.newPrivateChatVC = self
        return result
    }()
    
    private lazy var scanQRCodePlaceholderVC: ScanQRCodePlaceholderVC = {
        let result = ScanQRCodePlaceholderVC()
        result.newPrivateChatVC = self
        return result
    }()
    
    private lazy var scanQRCodeWrapperVC: ScanQRCodeWrapperVC = {
        let message = NSLocalizedString("vc_create_private_chat_scan_qr_code_explanation", comment: "")
        let result = ScanQRCodeWrapperVC(message: message)
        result.delegate = self
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle(NSLocalizedString("vc_create_private_chat_title", comment: ""))
        let navigationBar = navigationController!.navigationBar
        // Set up navigation bar buttons
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.tintColor = Colors.text
        navigationItem.leftBarButtonItem = closeButton
        // Set up page VC
        let hasCameraAccess = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        pages = [ enterPublicKeyVC, (hasCameraAccess ? scanQRCodeWrapperVC : scanQRCodePlaceholderVC) ]
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.setViewControllers([ enterPublicKeyVC ], direction: .forward, animated: false, completion: nil)
        // Set up tab bar
        view.addSubview(tabBar)
        tabBar.pin(.leading, to: .leading, of: view)
        let tabBarInset: CGFloat
        if #available(iOS 13, *) {
            tabBarInset = navigationBar.height()
        } else {
            tabBarInset = 0
        }
        tabBar.pin(.top, to: .top, of: view, withInset: tabBarInset)
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
        enterPublicKeyVC.constrainHeight(to: height)
        scanQRCodePlaceholderVC.constrainHeight(to: height)
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
            let alert = UIAlertController(title: NSLocalizedString("invalid_session_id", comment: ""), message: NSLocalizedString("Please check the Session ID and try again", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            presentAlert(alert)
        } else {
            let thread = TSContactThread.getOrCreateThread(contactId: hexEncodedPublicKey)
            presentingViewController?.dismiss(animated: true, completion: nil)
            SignalApp.shared().presentConversation(for: thread, action: .compose, animated: false)
        }
    }
}

private final class EnterPublicKeyVC : UIViewController {
    weak var newPrivateChatVC: NewPrivateChatVC!
    
    private lazy var userHexEncodedPublicKey: String = {
        if let masterHexEncodedPublicKey = UserDefaults.standard[.masterHexEncodedPublicKey] {
            return masterHexEncodedPublicKey
        } else {
            return getUserHexEncodedPublicKey()
        }
    }()
    
    // MARK: Components
    private lazy var publicKeyTextField = TextField(placeholder: NSLocalizedString("vc_enter_public_key_text_field_hint", comment: ""))
    
    private lazy var copyButton: Button = {
        let result = Button(style: .unimportant, size: .medium)
        result.setTitle(NSLocalizedString("copy", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(copyPublicKey), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Remove background color
        view.backgroundColor = .clear
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text.withAlphaComponent(Values.unimportantElementOpacity)
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = NSLocalizedString("vc_enter_public_key_explanation", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up separator
        let separator = Separator(title: NSLocalizedString("your_session_id", comment: ""))
        // Set up user public key label
        let userPublicKeyLabel = UILabel()
        userPublicKeyLabel.textColor = Colors.text
        userPublicKeyLabel.font = Fonts.spaceMono(ofSize: Values.mediumFontSize)
        userPublicKeyLabel.numberOfLines = 0
        userPublicKeyLabel.textAlignment = .center
        userPublicKeyLabel.lineBreakMode = .byCharWrapping
        userPublicKeyLabel.text = userHexEncodedPublicKey
        // Set up share button
        let shareButton = Button(style: .unimportant, size: .medium)
        shareButton.setTitle(NSLocalizedString("share", comment: ""), for: UIControl.State.normal)
        shareButton.addTarget(self, action: #selector(sharePublicKey), for: UIControl.Event.touchUpInside)
        // Set up button container
        let buttonContainer = UIStackView(arrangedSubviews: [ copyButton, shareButton ])
        buttonContainer.axis = .horizontal
        buttonContainer.spacing = Values.mediumSpacing
        buttonContainer.distribution = .fillEqually
        // Next button
        let nextButton = Button(style: .prominentOutline, size: .large)
        nextButton.setTitle(NSLocalizedString("next", comment: ""), for: UIControl.State.normal)
        nextButton.addTarget(self, action: #selector(startNewPrivateChatIfPossible), for: UIControl.Event.touchUpInside)
        let nextButtonContainer = UIView()
        nextButtonContainer.addSubview(nextButton)
        nextButton.pin(.leading, to: .leading, of: nextButtonContainer, withInset: 80)
        nextButton.pin(.top, to: .top, of: nextButtonContainer)
        nextButtonContainer.pin(.trailing, to: .trailing, of: nextButton, withInset: 80)
        nextButtonContainer.pin(.bottom, to: .bottom, of: nextButton)
        // Set up stack view
        let stackView = UIStackView(arrangedSubviews: [ publicKeyTextField, UIView.spacer(withHeight: Values.smallSpacing), explanationLabel, UIView.spacer(withHeight: Values.largeSpacing), separator, UIView.spacer(withHeight: Values.veryLargeSpacing), userPublicKeyLabel, UIView.spacer(withHeight: Values.veryLargeSpacing), buttonContainer, UIView.vStretchingSpacer(), nextButtonContainer ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: Values.largeSpacing, left: Values.largeSpacing, bottom: Values.largeSpacing, right: Values.largeSpacing)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.pin(to: view)
        // Set up width constraint
        view.set(.width, to: UIScreen.main.bounds.width)
        // Dismiss keyboard on tap
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGestureRecognizer)
    }
    
    // MARK: General
    func constrainHeight(to height: CGFloat) {
        view.set(.height, to: height)
    }
    
    @objc private func dismissKeyboard() {
        publicKeyTextField.resignFirstResponder()
    }
    
    @objc private func enableCopyButton() {
        copyButton.isUserInteractionEnabled = true
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle(NSLocalizedString("copy", comment: ""), for: UIControl.State.normal)
        }, completion: nil)
    }
    
    // MARK: Interaction
    @objc private func copyPublicKey() {
        UIPasteboard.general.string = userHexEncodedPublicKey
        copyButton.isUserInteractionEnabled = false
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle("Copied", for: UIControl.State.normal)
        }, completion: nil)
        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(enableCopyButton), userInfo: nil, repeats: false)
    }
    
    @objc private func sharePublicKey() {
        let shareVC = UIActivityViewController(activityItems: [ userHexEncodedPublicKey ], applicationActivities: nil)
        newPrivateChatVC.navigationController!.present(shareVC, animated: true, completion: nil)
    }
    
    @objc private func startNewPrivateChatIfPossible() {
        let hexEncodedPublicKey = publicKeyTextField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        newPrivateChatVC.startNewPrivateChatIfPossible(with: hexEncodedPublicKey)
    }
}

private final class ScanQRCodePlaceholderVC : UIViewController {
    weak var newPrivateChatVC: NewPrivateChatVC!
    
    override func viewDidLoad() {
        // Remove background color
        view.backgroundColor = .clear
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = NSLocalizedString("vc_scan_qr_code_camera_access_explanation", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up call to action button
        let callToActionButton = UIButton()
        callToActionButton.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        callToActionButton.setTitleColor(Colors.accent, for: UIControl.State.normal)
        callToActionButton.setTitle(NSLocalizedString("vc_scan_qr_code_grant_camera_access_button_title", comment: ""), for: UIControl.State.normal)
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
                self?.newPrivateChatVC.handleCameraAccessGranted()
            } else {
                // Do nothing
            }
        })
    }
}


final class LinkDeviceVC : BaseVC, UIPageViewControllerDataSource, UIPageViewControllerDelegate, OWSQRScannerDelegate {
    private let pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    private var pages: [UIViewController] = []
    private var targetVCIndex: Int?
    var delegate: LinkDeviceVCDelegate?
    
    // MARK: Components
    private lazy var tabBar: TabBar = {
        let tabs = [
            TabBar.Tab(title: NSLocalizedString("vc_link_device_enter_session_id_tab_title", comment: "")) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[0] ], direction: .forward, animated: false, completion: nil)
            },
            TabBar.Tab(title: NSLocalizedString("vc_link_device_scan_qr_code_tab_title", comment: "")) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[1] ], direction: .forward, animated: false, completion: nil)
            }
        ]
        return TabBar(tabs: tabs)
    }()
    
    private lazy var enterPublicKeyVC: EnterPublicKeyVC = {
        let result = EnterPublicKeyVC()
        result.linkDeviceVC = self
        return result
    }()
    
    private lazy var scanQRCodePlaceholderVC: ScanQRCodePlaceholderVC = {
        let result = ScanQRCodePlaceholderVC()
        result.linkDeviceVC = self
        return result
    }()
    
    private lazy var scanQRCodeWrapperVC: ScanQRCodeWrapperVC = {
        let message = NSLocalizedString("vc_link_device_scan_qr_code_explanation", comment: "")
        let result = ScanQRCodeWrapperVC(message: message)
        result.delegate = self
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle(NSLocalizedString("vc_link_device_title", comment: ""))
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
        requestDeviceLink(with: hexEncodedPublicKey)
    }
    
    fileprivate func requestDeviceLink(with hexEncodedPublicKey: String) {
        dismiss(animated: true) {
            self.delegate?.requestDeviceLink(with: hexEncodedPublicKey)
        }
    }
}

private final class EnterPublicKeyVC : UIViewController {
    weak var linkDeviceVC: LinkDeviceVC!
    private var spacer1HeightConstraint: NSLayoutConstraint!
    private var spacer2HeightConstraint: NSLayoutConstraint!
    private var spacer3HeightConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!
    private var linkButtonBottomOffsetConstraint: NSLayoutConstraint!
    
    // MARK: Components
    private lazy var publicKeyTextField: TextField = {
        if isIPhone6OrSmaller {
            return TextField(placeholder: NSLocalizedString("vc_enter_session_id_text_field_hint", comment: ""), customHeight: 56, customVerticalInset: 12)
        } else {
            return TextField(placeholder: NSLocalizedString("vc_enter_session_id_text_field_hint", comment: ""))
        }
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Remove background color
        view.backgroundColor = .clear
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: isIPhone6OrSmaller ? Values.largeFontSize : Values.veryLargeFontSize)
        titleLabel.text = NSLocalizedString("vc_enter_session_id_title", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = "vc_enter_session_id_explanation"
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        // Link button
        let linkButton = Button(style: .prominentOutline, size: .large)
        linkButton.setTitle(NSLocalizedString("continue_2", comment: ""), for: UIControl.State.normal)
        linkButton.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        linkButton.addTarget(self, action: #selector(requestDeviceLink), for: UIControl.Event.touchUpInside)
        let linkButtonContainer = UIView()
        linkButtonContainer.addSubview(linkButton)
        linkButton.pin(.leading, to: .leading, of: linkButtonContainer, withInset: Values.massiveSpacing)
        linkButton.pin(.top, to: .top, of: linkButtonContainer)
        linkButtonContainer.pin(.trailing, to: .trailing, of: linkButton, withInset: Values.massiveSpacing)
        linkButtonContainer.pin(.bottom, to: .bottom, of: linkButton)
        // Set up spacers
        let topSpacer = UIView.vStretchingSpacer()
        let spacer1 = UIView()
        spacer1HeightConstraint = spacer1.set(.height, to: isIPhone6OrSmaller ? Values.smallSpacing : Values.veryLargeSpacing)
        let spacer2 = UIView()
        spacer2HeightConstraint = spacer2.set(.height, to: isIPhone6OrSmaller ? Values.smallSpacing : Values.veryLargeSpacing)
        let bottomSpacer = UIView.vStretchingSpacer()
        let linkButtonBottomOffsetSpacer = UIView()
        linkButtonBottomOffsetConstraint = linkButtonBottomOffsetSpacer.set(.height, to: Values.onboardingButtonBottomOffset)
        // Set up top stack view
        let topStackView = UIStackView(arrangedSubviews: [ titleLabel, spacer1, explanationLabel, spacer2, publicKeyTextField ])
        topStackView.axis = .vertical
        // Set up top stack view container
        let topStackViewContainer = UIView()
        topStackViewContainer.addSubview(topStackView)
        topStackView.pin(.leading, to: .leading, of: topStackViewContainer, withInset: Values.veryLargeSpacing)
        topStackView.pin(.top, to: .top, of: topStackViewContainer)
        topStackViewContainer.pin(.trailing, to: .trailing, of: topStackView, withInset: Values.veryLargeSpacing)
        topStackViewContainer.pin(.bottom, to: .bottom, of: topStackView)
        // Set up stack view
        let stackView = UIStackView(arrangedSubviews: [ topSpacer, topStackViewContainer, bottomSpacer, linkButtonContainer, linkButtonBottomOffsetSpacer ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        view.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: view)
        stackView.pin(.top, to: .top, of: view)
        stackView.pin(.trailing, to: .trailing, of: view)
        bottomConstraint = stackView.pin(.bottom, to: .bottom, of: view)
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor, multiplier: 1).isActive = true
        // Set up width constraint
        view.set(.width, to: UIScreen.main.bounds.width)
        // Dismiss keyboard on tap
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGestureRecognizer)
        // Listen to keyboard notifications
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleKeyboardWillChangeFrameNotification(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleKeyboardWillHideNotification(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: General
    func constrainHeight(to height: CGFloat) {
        view.set(.height, to: height)
    }
    
    @objc private func dismissKeyboard() {
        publicKeyTextField.resignFirstResponder()
    }
    
    // MARK: Updating
    @objc private func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
        guard let newHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.size.height else { return }
        bottomConstraint.constant = -newHeight
        linkButtonBottomOffsetConstraint.constant = isIPhone6OrSmaller ? Values.smallSpacing : Values.largeSpacing
        spacer1HeightConstraint.constant = isIPhone6OrSmaller ? Values.smallSpacing : Values.mediumSpacing
        spacer2HeightConstraint.constant = isIPhone6OrSmaller ? Values.smallSpacing : Values.mediumSpacing
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func handleKeyboardWillHideNotification(_ notification: Notification) {
        bottomConstraint.constant = 0
        linkButtonBottomOffsetConstraint.constant = Values.onboardingButtonBottomOffset
        spacer1HeightConstraint.constant = isIPhone6OrSmaller ? Values.smallSpacing : Values.veryLargeSpacing
        spacer2HeightConstraint.constant = isIPhone6OrSmaller ? Values.smallSpacing : Values.veryLargeSpacing
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: Interaction
    @objc private func requestDeviceLink() {
        let hexEncodedPublicKey = publicKeyTextField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        linkDeviceVC.requestDeviceLink(with: hexEncodedPublicKey)
    }
}

private final class ScanQRCodePlaceholderVC : UIViewController {
    weak var linkDeviceVC: LinkDeviceVC!
    
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
                self?.linkDeviceVC.handleCameraAccessGranted()
            } else {
                // Do nothing
            }
        })
    }
}

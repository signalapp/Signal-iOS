
final class JoinPublicChatVC : BaseVC, UIPageViewControllerDataSource, UIPageViewControllerDelegate, OWSQRScannerDelegate {
    private let pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    private var pages: [UIViewController] = []
    private var isJoining = false
    private var targetVCIndex: Int?
    
    // MARK: Components
    private lazy var tabBar: TabBar = {
        let tabs = [
            TabBar.Tab(title: NSLocalizedString("vc_join_public_chat_enter_group_url_tab_title", comment: "")) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[0] ], direction: .forward, animated: false, completion: nil)
            },
            TabBar.Tab(title: NSLocalizedString("vc_join_public_chat_scan_qr_code_tab_title", comment: "")) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[1] ], direction: .forward, animated: false, completion: nil)
            }
        ]
        return TabBar(tabs: tabs)
    }()
    
    private lazy var enterChatURLVC: EnterChatURLVC = {
        let result = EnterChatURLVC()
        result.joinPublicChatVC = self
        return result
    }()
    
    private lazy var scanQRCodePlaceholderVC: ScanQRCodePlaceholderVC = {
        let result = ScanQRCodePlaceholderVC()
        result.joinPublicChatVC = self
        return result
    }()
    
    private lazy var scanQRCodeWrapperVC: ScanQRCodeWrapperVC = {
        let message = NSLocalizedString("vc_join_public_chat_scan_qr_code_explanation", comment: "")
        let result = ScanQRCodeWrapperVC(message: message)
        result.delegate = self
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle(NSLocalizedString("vc_join_public_chat_title", comment: ""))
        let navigationBar = navigationController!.navigationBar
        // Set up navigation bar buttons
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.tintColor = Colors.text
        navigationItem.leftBarButtonItem = closeButton
        // Set up page VC
        let hasCameraAccess = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        pages = [ enterChatURLVC, (hasCameraAccess ? scanQRCodeWrapperVC : scanQRCodePlaceholderVC) ]
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.setViewControllers([ enterChatURLVC ], direction: .forward, animated: false, completion: nil)
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
        enterChatURLVC.constrainHeight(to: height)
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
        let chatURL = string
        joinPublicChatIfPossible(with: chatURL)
    }
    
    fileprivate func joinPublicChatIfPossible(with chatURL: String) {
        guard !isJoining else { return }
        guard let url = URL(string: chatURL), let scheme = url.scheme, scheme == "https", url.host != nil else {
            return showError(title: NSLocalizedString("invalid_url", comment: ""), message: "Please check the URL you entered and try again")
        }
        isJoining = true
        let channelID: UInt64 = 1
        let urlAsString = url.absoluteString
        let userPublicKey = UserDefaults.standard[.masterHexEncodedPublicKey] ?? getUserHexEncodedPublicKey()
        let profileManager = OWSProfileManager.shared()
        let displayName = profileManager.profileNameForRecipient(withID: userPublicKey)
        let profilePictureURL = profileManager.profilePictureURL()
        let profileKey = profileManager.localProfileKey().keyData
        try! Storage.writeSync { transaction in
            transaction.removeObject(forKey: "\(urlAsString).\(channelID)", inCollection: PublicChatAPI.lastMessageServerIDCollection)
            transaction.removeObject(forKey: "\(urlAsString).\(channelID)", inCollection: PublicChatAPI.lastDeletionServerIDCollection)
        }
        ModalActivityIndicatorViewController.present(fromViewController: navigationController!, canCancel: false) { [weak self] _ in
            PublicChatManager.shared.addChat(server: urlAsString, channel: channelID)
            .done(on: DispatchQueue.main) { [weak self] _ in
                let _ = PublicChatAPI.setDisplayName(to: displayName, on: urlAsString)
                let _ = PublicChatAPI.setProfilePictureURL(to: profilePictureURL, using: profileKey, on: urlAsString)
                let _ = PublicChatAPI.join(channelID, on: urlAsString)
                let syncManager = SSKEnvironment.shared.syncManager
                let _ = syncManager.syncAllOpenGroups()
                self?.presentingViewController!.dismiss(animated: true, completion: nil)
            }
            .catch(on: DispatchQueue.main) { [weak self] error in
                self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                var title = "Couldn't Join"
                var message = ""
                if case OnionRequestAPI.Error.httpRequestFailedAtTargetSnode(statusCode: let statusCode, json: _) = error, statusCode == 401 || statusCode == 403 {
                    title = "Unauthorized"
                    message = "Please ask the open group operator to add you to the group."
                }
                self?.isJoining = false
                self?.showError(title: title, message: message)
            }
        }
    }
    
    // MARK: Convenience
    private func showError(title: String, message: String = "") {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
        presentAlert(alert)
    }
}

private final class EnterChatURLVC : UIViewController {
    weak var joinPublicChatVC: JoinPublicChatVC!
    private var bottomConstraint: NSLayoutConstraint!
    
    // MARK: Components
    private lazy var chatURLTextField: TextField = {
        let result = TextField(placeholder: NSLocalizedString("vc_enter_chat_url_text_field_hint", comment: ""))
        result.keyboardType = .URL
        result.autocapitalizationType = .none
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Remove background color
        view.backgroundColor = .clear
        // Next button
        let nextButton = Button(style: .prominentOutline, size: .large)
        nextButton.setTitle(NSLocalizedString("next", comment: ""), for: UIControl.State.normal)
        nextButton.addTarget(self, action: #selector(joinPublicChatIfPossible), for: UIControl.Event.touchUpInside)
        let nextButtonContainer = UIView()
        nextButtonContainer.addSubview(nextButton)
        nextButton.pin(.leading, to: .leading, of: nextButtonContainer, withInset: 80)
        nextButton.pin(.top, to: .top, of: nextButtonContainer)
        nextButtonContainer.pin(.trailing, to: .trailing, of: nextButton, withInset: 80)
        nextButtonContainer.pin(.bottom, to: .bottom, of: nextButton)
        // Set up stack view
        let stackView = UIStackView(arrangedSubviews: [ chatURLTextField, UIView.vStretchingSpacer(), nextButtonContainer ])
        stackView.axis = .vertical
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
        chatURLTextField.resignFirstResponder()
    }
    
    // MARK: Updating
    @objc private func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
        guard let newHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.size.height else { return }
        bottomConstraint.constant = newHeight
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func handleKeyboardWillHideNotification(_ notification: Notification) {
        bottomConstraint.constant = 0
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: Interaction
    @objc private func joinPublicChatIfPossible() {
        var chatURL = chatURLTextField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        if !chatURL.lowercased().starts(with: "http") {
            chatURL = "https://" + chatURL
        }
        joinPublicChatVC.joinPublicChatIfPossible(with: chatURL)
    }
}

private final class ScanQRCodePlaceholderVC : UIViewController {
    weak var joinPublicChatVC: JoinPublicChatVC!
    
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
                self?.joinPublicChatVC.handleCameraAccessGranted()
            } else {
                // Do nothing
            }
        })
    }
}

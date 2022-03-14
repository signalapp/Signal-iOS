
final class JoinOpenGroupVC : BaseVC, UIPageViewControllerDataSource, UIPageViewControllerDelegate, OWSQRScannerDelegate {
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
    
    private lazy var enterURLVC: EnterURLVC = {
        let result = EnterURLVC()
        result.joinOpenGroupVC = self
        return result
    }()
    
    private lazy var scanQRCodePlaceholderVC: ScanQRCodePlaceholderVC = {
        let result = ScanQRCodePlaceholderVC()
        result.joinOpenGroupVC = self
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
        // Navigation bar buttons
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.tintColor = Colors.text
        navigationItem.leftBarButtonItem = closeButton
        // Page VC
        let hasCameraAccess = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        pages = [ enterURLVC, (hasCameraAccess ? scanQRCodeWrapperVC : scanQRCodePlaceholderVC) ]
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.setViewControllers([ enterURLVC ], direction: .forward, animated: false, completion: nil)
        // Tab bar
        view.addSubview(tabBar)
        tabBar.pin(.leading, to: .leading, of: view)
        let tabBarInset: CGFloat
        if #available(iOS 13, *) {
            tabBarInset = UIDevice.current.isIPad ? navigationBar.height() + 20 : navigationBar.height()
        } else {
            tabBarInset = 0
        }
        tabBar.pin(.top, to: .top, of: view, withInset: tabBarInset)
        view.pin(.trailing, to: .trailing, of: tabBar)
        // Page VC constraints
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
            height = navigationController!.view.bounds.height - navigationBar.height() - TabBar.snHeight
        } else {
            let statusBarHeight = UIApplication.shared.statusBarFrame.height
            height = navigationController!.view.bounds.height - navigationBar.height() - TabBar.snHeight - statusBarHeight
        }
        pageVCView.set(.height, to: height)
        enterURLVC.constrainHeight(to: height)
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
        joinOpenGroup(with: string)
    }
    
    fileprivate func joinOpenGroup(with string: String) {
        // A V2 open group URL will look like: <optional scheme> + <host> + <optional port> + <room> + <public key>
        // The host doesn't parse if no explicit scheme is provided
        if let (room, server, publicKey) = OpenGroupManagerV2.parseV2OpenGroup(from: string) {
            joinV2OpenGroup(room: room, server: server, publicKey: publicKey)
        } else {
            let title = NSLocalizedString("invalid_url", comment: "")
            let message = "Please check the URL you entered and try again."
            showError(title: title, message: message)
        }
    }
    
    fileprivate func joinV2OpenGroup(room: String, server: String, publicKey: String) {
        guard !isJoining else { return }
        isJoining = true
        ModalActivityIndicatorViewController.present(fromViewController: navigationController!, canCancel: false) { [weak self] _ in
            Storage.shared.write { transaction in
                OpenGroupManagerV2.shared.add(room: room, server: server, publicKey: publicKey, using: transaction)
                .done(on: DispatchQueue.main) { [weak self] _ in
                    self?.presentingViewController?.dismiss(animated: true, completion: nil)
                    let appDelegate = UIApplication.shared.delegate as! AppDelegate
                    appDelegate.forceSyncConfigurationNowIfNeeded().retainUntilComplete() // FIXME: It's probably cleaner to do this inside addOpenGroup(...)
                }
                .catch(on: DispatchQueue.main) { [weak self] error in
                    self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                    let title = "Couldn't Join"
                    let message = error.localizedDescription
                    self?.isJoining = false
                    self?.showError(title: title, message: message)
                }
            }
        }
    }
    
    // MARK: Convenience
    private func showError(title: String, message: String = "") {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_OK", comment: ""), style: .default, handler: nil))
        presentAlert(alert)
    }
}

private final class EnterURLVC : UIViewController, UIGestureRecognizerDelegate, OpenGroupSuggestionGridDelegate {
    weak var joinOpenGroupVC: JoinOpenGroupVC!
    private var isKeyboardShowing = false
    private var bottomConstraint: NSLayoutConstraint!
    private let bottomMargin: CGFloat = UIDevice.current.isIPad ? Values.largeSpacing : 0
    
    // MARK: Components
    private lazy var urlTextView: TextView = {
        let result = TextView(placeholder: NSLocalizedString("vc_enter_chat_url_text_field_hint", comment: ""))
        result.keyboardType = .URL
        result.autocapitalizationType = .none
        result.autocorrectionType = .no
        return result
    }()
    
    private lazy var suggestionGrid: OpenGroupSuggestionGrid = {
        let maxWidth = UIScreen.main.bounds.width - Values.largeSpacing * 2
        let result = OpenGroupSuggestionGrid(maxWidth: maxWidth)
        result.delegate = self
        return result
    }()
    
    private lazy var suggestionGridTitleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.largeFontSize)
        result.text = NSLocalizedString("vc_join_open_group_suggestions_title", comment: "")
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Remove background color
        view.backgroundColor = .clear
        // Next button
        let nextButton = Button(style: .prominentOutline, size: .large)
        nextButton.setTitle(NSLocalizedString("next", comment: ""), for: UIControl.State.normal)
        nextButton.addTarget(self, action: #selector(joinOpenGroup), for: UIControl.Event.touchUpInside)
        let nextButtonContainer = UIView(wrapping: nextButton, withInsets: UIEdgeInsets(top: 0, leading: 80, bottom: 0, trailing: 80), shouldAdaptForIPadWithWidth: Values.iPadButtonWidth)
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ urlTextView, UIView.spacer(withHeight: Values.mediumSpacing), suggestionGridTitleLabel, UIView.spacer(withHeight: Values.mediumSpacing), suggestionGrid, UIView.vStretchingSpacer(), nextButtonContainer ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(uniform: Values.largeSpacing)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: view)
        stackView.pin(.top, to: .top, of: view)
        view.pin(.trailing, to: .trailing, of: stackView)
        bottomConstraint = view.pin(.bottom, to: .bottom, of: stackView, withInset: bottomMargin)
        // Constraints
        view.set(.width, to: UIScreen.main.bounds.width)
        // Dismiss keyboard on tap
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGestureRecognizer.delegate = self
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
        urlTextView.resignFirstResponder()
    }
    
    // MARK: Interaction
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let location = gestureRecognizer.location(in: view)
        return !suggestionGrid.frame.contains(location)
    }
    
    func join(_ room: OpenGroupAPIV2.Info) {
        joinOpenGroupVC.joinV2OpenGroup(room: room.id, server: OpenGroupAPIV2.defaultServer, publicKey: OpenGroupAPIV2.defaultServerPublicKey)
    }
    
    @objc private func joinOpenGroup() {
        let url = urlTextView.text?.trimmingCharacters(in: .whitespaces) ?? ""
        joinOpenGroupVC.joinOpenGroup(with: url)
    }
    
    // MARK: Updating
    @objc private func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
        guard !isKeyboardShowing else { return }
        isKeyboardShowing = true
        guard let newHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.size.height else { return }
        bottomConstraint.constant = newHeight + bottomMargin
        UIView.animate(withDuration: 0.25, animations: {
            self.view.layoutIfNeeded()
            self.suggestionGridTitleLabel.alpha = 0
            self.suggestionGrid.alpha = 0
        }, completion: { _ in
            self.suggestionGridTitleLabel.isHidden = true
            self.suggestionGrid.isHidden = true
        })
    }
    
    @objc private func handleKeyboardWillHideNotification(_ notification: Notification) {
        guard isKeyboardShowing else { return }
        isKeyboardShowing = false
        bottomConstraint.constant = bottomMargin
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
            self.suggestionGridTitleLabel.isHidden = false
            self.suggestionGridTitleLabel.alpha = 1
            self.suggestionGrid.isHidden = false
            self.suggestionGrid.alpha = 1
        }
    }
}

private final class ScanQRCodePlaceholderVC : UIViewController {
    weak var joinOpenGroupVC: JoinOpenGroupVC!
    
    override func viewDidLoad() {
        // Remove background color
        view.backgroundColor = .clear
        // Explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = NSLocalizedString("vc_scan_qr_code_camera_access_explanation", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        // Call to action button
        let callToActionButton = UIButton()
        callToActionButton.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        callToActionButton.setTitleColor(Colors.accent, for: UIControl.State.normal)
        callToActionButton.setTitle(NSLocalizedString("vc_scan_qr_code_grant_camera_access_button_title", comment: ""), for: UIControl.State.normal)
        callToActionButton.addTarget(self, action: #selector(requestCameraAccess), for: UIControl.Event.touchUpInside)
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ explanationLabel, callToActionButton ])
        stackView.axis = .vertical
        stackView.spacing = Values.mediumSpacing
        stackView.alignment = .center
        // Constraints
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
                self?.joinOpenGroupVC.handleCameraAccessGranted()
            } else {
                // Do nothing
            }
        })
    }
}

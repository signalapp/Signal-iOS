// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

final class JoinOpenGroupVC: BaseVC, UIPageViewControllerDataSource, UIPageViewControllerDelegate, OWSQRScannerDelegate {
    private let pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    private var pages: [UIViewController] = []
    private var isJoining = false
    private var targetVCIndex: Int?

    // MARK: - Components
    
    private lazy var tabBar: TabBar = {
        let tabs: [TabBar.Tab] = [
            TabBar.Tab(title: "vc_join_public_chat_enter_group_url_tab_title".localized()) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[0] ], direction: .forward, animated: false, completion: nil)
            },
            TabBar.Tab(title: "vc_join_public_chat_scan_qr_code_tab_title".localized()) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[1] ], direction: .forward, animated: false, completion: nil)
            }
        ]
        
        return TabBar(tabs: tabs)
    }()

    private lazy var enterURLVC: EnterURLVC = {
        let result: EnterURLVC = EnterURLVC()
        result.joinOpenGroupVC = self
        
        return result
    }()

    private lazy var scanQRCodePlaceholderVC: ScanQRCodePlaceholderVC = {
        let result: ScanQRCodePlaceholderVC = ScanQRCodePlaceholderVC()
        result.joinOpenGroupVC = self
        
        return result
    }()

    private lazy var scanQRCodeWrapperVC: ScanQRCodeWrapperVC = {
        let result: ScanQRCodeWrapperVC = ScanQRCodeWrapperVC(message: nil)
        result.delegate = self
        
        return result
    }()

    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle("vc_join_public_chat_title".localized())
        
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.tintColor = Colors.text
        navigationItem.rightBarButtonItem = closeButton
        
        // Page VC
        let hasCameraAccess = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        pages = [ enterURLVC, (hasCameraAccess ? scanQRCodeWrapperVC : scanQRCodePlaceholderVC) ]
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.setViewControllers([ enterURLVC ], direction: .forward, animated: false, completion: nil)
        
        // Tab bar
        view.addSubview(tabBar)
        tabBar.pin(.leading, to: .leading, of: view)
        tabBar.pin(.top, to: .top, of: view)
        tabBar.pin(.trailing, to: .trailing, of: view)
        
        // Page VC constraints
        let pageVCView = pageVC.view!
        view.addSubview(pageVCView)
        pageVCView.pin(.leading, to: .leading, of: view)
        pageVCView.pin(.top, to: .bottom, of: tabBar)
        pageVCView.pin(.trailing, to: .trailing, of: view)
        pageVCView.pin(.bottom, to: .bottom, of: view)
        let navBarHeight: CGFloat = (navigationController?.navigationBar.frame.size.height ?? 0)
        let height: CGFloat = ((navigationController?.view.bounds.height ?? 0) - navBarHeight - TabBar.snHeight)
        enterURLVC.constrainHeight(to: height)
        scanQRCodePlaceholderVC.constrainHeight(to: height)
    }

    // MARK: - General
    
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

    // MARK: - Updating
    
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        guard let targetVC = pendingViewControllers.first, let index = pages.firstIndex(of: targetVC) else { return }
        
        targetVCIndex = index
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating isFinished: Bool, previousViewControllers: [UIViewController], transitionCompleted isCompleted: Bool) {
        guard isCompleted, let index = targetVCIndex else { return }
        
        tabBar.selectTab(at: index)
    }

    // MARK: - Interaction
    
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }

    func controller(_ controller: OWSQRCodeScanningViewController, didDetectQRCodeWith string: String) {
        joinOpenGroup(with: string)
    }

    fileprivate func joinOpenGroup(with urlString: String) {
        // A V2 open group URL will look like: <optional scheme> + <host> + <optional port> + <room> + <public key>
        // The host doesn't parse if no explicit scheme is provided
        guard let (room, server, publicKey) = OpenGroupManager.parseOpenGroup(from: urlString) else {
            showError(
                title: "invalid_url".localized(),
                message: "Please check the URL you entered and try again."
            )
            return
        }
        
        joinOpenGroup(roomToken: room, server: server, publicKey: publicKey)
    }

    fileprivate func joinOpenGroup(roomToken: String, server: String, publicKey: String, shouldOpenCommunity: Bool = false) {
        guard !isJoining, let navigationController: UINavigationController = navigationController else { return }
        
        isJoining = true
        
        ModalActivityIndicatorViewController.present(fromViewController: navigationController, canCancel: false) { [weak self] _ in
            Storage.shared
                .writeAsync { db in
                    OpenGroupManager.shared.add(
                        db,
                        roomToken: roomToken,
                        server: server,
                        publicKey: publicKey,
                        isConfigMessage: false
                    )
                }
                .done(on: DispatchQueue.main) { [weak self] _ in
                    Storage.shared.writeAsync { db in
                        try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete() // FIXME: It's probably cleaner to do this inside addOpenGroup(...)
                    }
                    
                    self?.presentingViewController?.dismiss(animated: true, completion: nil)
                    
                    if shouldOpenCommunity {
                        SessionApp.presentConversation(
                            for: OpenGroup.idFor(roomToken: roomToken, server: server),
                            threadVariant: .openGroup,
                            isMessageRequest: false,
                            action: .compose,
                            focusInteractionId: nil,
                            animated: false
                        )
                    }
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

    // MARK: - Convenience

    private func showError(title: String, message: String = "") {
        let alert: UIAlertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "BUTTON_OK".localized(), style: .default, handler: nil))
        
        presentAlert(alert)
    }
}

private final class EnterURLVC: UIViewController, UIGestureRecognizerDelegate, OpenGroupSuggestionGridDelegate {
    weak var joinOpenGroupVC: JoinOpenGroupVC?
    
    private var isKeyboardShowing = false
    private var bottomConstraint: NSLayoutConstraint!
    private let bottomMargin: CGFloat = (UIDevice.current.isIPad ? Values.largeSpacing : 0)

    // MARK: - UI
    
    private lazy var urlTextView: TextView = {
        let result: TextView = TextView(placeholder: "vc_enter_chat_url_text_field_hint".localized())
        result.keyboardType = .URL
        result.autocapitalizationType = .none
        result.autocorrectionType = .no
        
        return result
    }()
    
    private lazy var suggestionGridTitleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.largeFontSize)
        result.text = "vc_join_open_group_suggestions_title".localized()
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.setContentHuggingPriority(.required, for: .vertical)
        
        return result
    }()

    private lazy var suggestionGrid: OpenGroupSuggestionGrid = {
        let maxWidth: CGFloat = (UIScreen.main.bounds.width - Values.largeSpacing * 2)
        let result: OpenGroupSuggestionGrid = OpenGroupSuggestionGrid(maxWidth: maxWidth)
        result.delegate = self
        
        return result
    }()

    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        // Remove background color
        view.backgroundColor = .clear
        
        // Next button
        let nextButton = Button(style: .prominentOutline, size: .large)
        nextButton.setTitle(NSLocalizedString("next", comment: ""), for: UIControl.State.normal)
        nextButton.addTarget(self, action: #selector(joinOpenGroup), for: UIControl.Event.touchUpInside)
        
        let nextButtonContainer = UIView(
            wrapping: nextButton,
            withInsets: UIEdgeInsets(top: 0, leading: 80, bottom: 0, trailing: 80),
            shouldAdaptForIPadWithWidth: Values.iPadButtonWidth
        )
        
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillChangeFrameNotification(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillHideNotification(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - General
    
    func constrainHeight(to height: CGFloat) {
        view.set(.height, to: height)
    }

    @objc private func dismissKeyboard() {
        urlTextView.resignFirstResponder()
    }

    // MARK: - Interaction
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let location = gestureRecognizer.location(in: view)
        
        return (
            (!suggestionGrid.isHidden && !suggestionGrid.frame.contains(location)) ||
            (suggestionGrid.isHidden && location.y > urlTextView.frame.maxY)
        )
    }
    
    func join(_ room: OpenGroupAPI.Room) {
        joinOpenGroupVC?.joinOpenGroup(
            roomToken: room.token,
            server: OpenGroupAPI.defaultServer,
            publicKey: OpenGroupAPI.defaultServerPublicKey,
            shouldOpenCommunity: true
        )
    }

    @objc private func joinOpenGroup() {
        let url = urlTextView.text?.trimmingCharacters(in: .whitespaces) ?? ""
        joinOpenGroupVC?.joinOpenGroup(with: url)
    }
    
    // MARK: - Updating
    
    @objc private func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
        guard !isKeyboardShowing else { return }
        isKeyboardShowing = true
        
        guard let endFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        guard endFrame.minY < UIScreen.main.bounds.height else { return }
        
        bottomConstraint.constant = endFrame.size.height + bottomMargin
        
        UIView.animate(
            withDuration: 0.25,
            animations: { [weak self] in
                self?.view.layoutIfNeeded()
                self?.suggestionGridTitleLabel.alpha = 0
                self?.suggestionGrid.alpha = 0
            },
            completion: { [weak self] _ in
                self?.suggestionGridTitleLabel.isHidden = true
                self?.suggestionGrid.isHidden = true
            }
        )
    }
    
    @objc private func handleKeyboardWillHideNotification(_ notification: Notification) {
        guard isKeyboardShowing else { return }
        
        isKeyboardShowing = false
        bottomConstraint.constant = bottomMargin
        
        UIView.animate(withDuration: 0.25) { [weak self] in
            self?.view.layoutIfNeeded()
            self?.suggestionGridTitleLabel.isHidden = false
            self?.suggestionGridTitleLabel.alpha = 1
            self?.suggestionGrid.isHidden = false
            self?.suggestionGrid.alpha = 1
        }
    }
}

private final class ScanQRCodePlaceholderVC: UIViewController {
    weak var joinOpenGroupVC: JoinOpenGroupVC?
    
    // MARK: - Lifecycle

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
                self?.joinOpenGroupVC?.handleCameraAccessGranted()
            } else {
                // Do nothing
            }
        })
    }
}

// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import AVFoundation
import GRDB
import Curve25519Kit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

final class NewDMVC: BaseVC, UIPageViewControllerDataSource, UIPageViewControllerDelegate, QRScannerDelegate {
    private let pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    private var pages: [UIViewController] = []
    private var targetVCIndex: Int?
    
    // MARK: - Components
    
    private lazy var tabBar: TabBar = {
        let tabs = [
            TabBar.Tab(title: "vc_create_private_chat_enter_session_id_tab_title".localized()) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[0] ], direction: .forward, animated: false, completion: nil)
            },
            TabBar.Tab(title: "vc_create_private_chat_scan_qr_code_tab_title".localized()) { [weak self] in
                guard let self = self else { return }
                self.pageVC.setViewControllers([ self.pages[1] ], direction: .forward, animated: false, completion: nil)
            }
        ]
        
        return TabBar(tabs: tabs)
    }()
    
    private lazy var enterPublicKeyVC: EnterPublicKeyVC = {
        let result = EnterPublicKeyVC()
        result.NewDMVC = self
        
        return result
    }()
    
    private lazy var scanQRCodePlaceholderVC: ScanQRCodePlaceholderVC = {
        let result = ScanQRCodePlaceholderVC()
        result.newDMVC = self
        
        return result
    }()
    
    private lazy var scanQRCodeWrapperVC: ScanQRCodeWrapperVC = {
        let message = "vc_create_private_chat_scan_qr_code_explanation".localized()
        let result = ScanQRCodeWrapperVC(message: message)
        result.delegate = self
        return result
    }()
    
    init(sessionID: String) {
        super.init(nibName: nil, bundle: nil)
        enterPublicKeyVC.setSessionID(to: sessionID)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override init(nibName: String?, bundle: Bundle?) {
        super.init(nibName: nibName, bundle: bundle)
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setNavBarTitle("vc_create_private_chat_title".localized())
        let navigationBar = navigationController!.navigationBar
        
        // Set up navigation bar buttons
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.themeTintColor = .textPrimary
        navigationItem.leftBarButtonItem = closeButton
        
        // Set up page VC
        let hasCameraAccess = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        pages = [ enterPublicKeyVC, (hasCameraAccess ? scanQRCodeWrapperVC : scanQRCodePlaceholderVC) ]
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.setViewControllers([ enterPublicKeyVC ], direction: .forward, animated: false, completion: nil)
        
        // Set up tab bar
        let tabBarInset: CGFloat = (UIDevice.current.isIPad ? navigationBar.height() + 20 : navigationBar.height())
        view.addSubview(tabBar)
        tabBar.pin(.leading, to: .leading, of: view)
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
        let height: CGFloat = (navigationController!.view.bounds.height - navigationBar.height() - TabBar.snHeight)
        pageVCView.set(.width, to: screen.width)
        pageVCView.set(.height, to: height)
        
        enterPublicKeyVC.constrainHeight(to: height)
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

    func controller(_ controller: QRCodeScanningViewController, didDetectQRCodeWith string: String) {
        let hexEncodedPublicKey = string
        startNewDMIfPossible(with: hexEncodedPublicKey)
    }
    
    fileprivate func startNewDMIfPossible(with onsNameOrPublicKey: String) {
        let maybeSessionId: SessionId? = SessionId(from: onsNameOrPublicKey)
        
        if ECKeyPair.isValidHexEncodedPublicKey(candidate: onsNameOrPublicKey) && maybeSessionId?.prefix == .standard {
            startNewDM(with: onsNameOrPublicKey)
            return
        }
        
        // This could be an ONS name
        ModalActivityIndicatorViewController
            .present(fromViewController: navigationController!, canCancel: false) { [weak self] modalActivityIndicator in
            SnodeAPI
                    .getSessionID(for: onsNameOrPublicKey)
                    .done { sessionID in
                        modalActivityIndicator.dismiss {
                            self?.startNewDM(with: sessionID)
                        }
                    }
                    .catch { error in
                        modalActivityIndicator.dismiss {
                            var messageOrNil: String?
                            if let error = error as? SnodeAPIError {
                                switch error {
                                    case .decryptionFailed, .hashingFailed, .validationFailed:
                                        messageOrNil = error.errorDescription
                                    default: break
                                }
                            }
                            let message: String = {
                                if let messageOrNil: String = messageOrNil {
                                    return messageOrNil
                                }
                                
                                return (maybeSessionId?.prefix == .blinded ?
                                    "You can only send messages to Blinded IDs from within an Open Group" :
                                    "Please check the Session ID or ONS name and try again"
                                )
                            }()
                            let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "BUTTON_OK".localized(), style: .default, handler: nil))
                            self?.presentAlert(alert)
                        }
                    }
        }
    }

    private func startNewDM(with sessionId: String) {
        let maybeThread: SessionThread? = Storage.shared.write { db in
            try SessionThread.fetchOrCreate(db, id: sessionId, variant: .contact)
        }
        
        guard maybeThread != nil else { return }
        
        presentingViewController?.dismiss(animated: true, completion: nil)
        
        SessionApp.presentConversation(for: sessionId, action: .compose, animated: false)
    }
}

// MARK: - EnterPublicKeyVC

private final class EnterPublicKeyVC: UIViewController {
    weak var NewDMVC: NewDMVC!
    private var isKeyboardShowing = false
    private var simulatorWillResignFirstResponder = false
    private var bottomConstraint: NSLayoutConstraint!
    private let bottomMargin: CGFloat = UIDevice.current.isIPad ? Values.largeSpacing : 0
    
    // MARK: - Components
    private lazy var publicKeyTextView: TextView = {
        let result = TextView(placeholder: "vc_enter_public_key_text_field_hint".localized())
        result.autocapitalizationType = .none
        
        return result
    }()
    
    private lazy var copyButton: OutlineButton = {
        let result = OutlineButton(style: .regular, size: .small)
        result.setTitle("copy".localized(), for: .normal)
        result.addTarget(self, action: #selector(copyPublicKey), for: .touchUpInside)
        
        return result
    }()
    
    private lazy var shareButton: OutlineButton = {
        let result = OutlineButton(style: .regular, size: .small)
        result.setTitle("share".localized(), for: .normal)
        result.addTarget(self, action: #selector(sharePublicKey), for: .touchUpInside)
        
        return result
    }()
    
    private lazy var nextButton: OutlineButton = {
        let result = OutlineButton(style: .regular, size: .large)
        result.setTitle("next".localized(), for: .normal)
        result.addTarget(self, action: #selector(startNewDMIfPossible), for: .touchUpInside)
        result.alpha = 0
        
        return result
    }()
    
    private lazy var userPublicKeyLabel: UILabel = {
        let result = UILabel()
        result.font = Fonts.spaceMono(ofSize: Values.mediumFontSize)
        result.text = getUserHexEncodedPublicKey()
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        result.lineBreakMode = .byCharWrapping
        result.numberOfLines = 0
        
        return result
    }()
    
    private lazy var spacer1 = UIView.spacer(withHeight: Values.largeSpacing)
    private lazy var spacer2 = UIView.spacer(withHeight: Values.largeSpacing)
    private lazy var spacer3 = UIView.spacer(withHeight: Values.largeSpacing)
    
    private lazy var separator = Separator(title: "your_session_id".localized())
    
    private lazy var buttonContainer: UIStackView = {
        let result = UIStackView()
        result.axis = .horizontal
        result.spacing = UIDevice.current.isIPad ? Values.iPadButtonSpacing : Values.mediumSpacing
        result.distribution = .fillEqually
        
        if (UIDevice.current.isIPad) {
            result.layoutMargins = UIEdgeInsets(top: 0, left: Values.iPadButtonContainerMargin, bottom: 0, right: Values.iPadButtonContainerMargin)
            result.isLayoutMarginsRelativeArrangement = true
        }
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        // Remove background color
        view.themeBackgroundColor = .clear
        
        // User session id container
        let userPublicKeyContainer = UIView(
            wrapping: userPublicKeyLabel,
            withInsets: .zero,
            shouldAdaptForIPadWithWidth: Values.iPadUserSessionIdContainerWidth
        )
        
        // Explanation label
        let explanationLabel = UILabel()
        explanationLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        explanationLabel.text = "vc_enter_public_key_explanation".localized()
        explanationLabel.themeTextColor = .textSecondary
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.numberOfLines = 0
        
        // Button container
        buttonContainer.addArrangedSubview(copyButton)
        buttonContainer.addArrangedSubview(shareButton)

        let nextButtonContainer = UIView(
            wrapping: nextButton,
            withInsets: UIEdgeInsets(top: 0, leading: 80, bottom: 0, trailing: 80),
            shouldAdaptForIPadWithWidth: Values.iPadButtonWidth
        )
        
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ publicKeyTextView, UIView.spacer(withHeight: Values.smallSpacing), explanationLabel, spacer1, separator, spacer2, userPublicKeyContainer, spacer3, buttonContainer, UIView.vStretchingSpacer(), nextButtonContainer ])
        mainStackView.axis = .vertical
        mainStackView.alignment = .fill
        mainStackView.layoutMargins = UIEdgeInsets(top: Values.largeSpacing, left: Values.largeSpacing, bottom: Values.largeSpacing, right: Values.largeSpacing)
        mainStackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: view)
        mainStackView.pin(.top, to: .top, of: view)
        view.pin(.trailing, to: .trailing, of: mainStackView)
        bottomConstraint = view.pin(.bottom, to: .bottom, of: mainStackView, withInset: bottomMargin)
        
        // Width constraint
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
    
    // MARK: - General
    
    func setSessionID(to sessionID: String){
        publicKeyTextView.insertText(sessionID)
    }

    func constrainHeight(to height: CGFloat) {
        view.set(.height, to: height)
    }
    
    @objc private func dismissKeyboard() {
        simulatorWillResignFirstResponder = true
        publicKeyTextView.resignFirstResponder()
        simulatorWillResignFirstResponder = false
    }
    
    @objc private func enableCopyButton() {
        copyButton.isUserInteractionEnabled = true
        
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle("copy".localized(), for: .normal)
        }, completion: nil)
    }
    
    // MARK: - Updating
    
    @objc private func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
        #if targetEnvironment(simulator)
        // Note: See 'handleKeyboardWillHideNotification' for the explanation
        guard !simulatorWillResignFirstResponder else { return }
        #else
        guard !isKeyboardShowing else { return }
        #endif
        
        isKeyboardShowing = true
        
        guard let newHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.size.height else { return }
        
        bottomConstraint.constant = newHeight + bottomMargin
        
        UIView.animate(withDuration: 0.25) {
            [ self.spacer1, self.separator, self.spacer2, self.userPublicKeyLabel, self.spacer3, self.buttonContainer ].forEach {
                $0.alpha = 0
                $0.isHidden = true
            }
            self.nextButton.alpha = 1
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func handleKeyboardWillHideNotification(_ notification: Notification) {
        #if targetEnvironment(simulator)
        // Note: On the simulator the keyboard won't appear by default (unless you enable
        // it) this results in the "keyboard will hide" notification incorrectly getting
        // triggered immediately - the 'simulatorWillResignFirstResponder' value is a workaround
        // to make this behave more like a real device when testing
        guard isKeyboardShowing && simulatorWillResignFirstResponder else { return }
        #else
        guard isKeyboardShowing else { return }
        #endif
        
        isKeyboardShowing = false
        bottomConstraint.constant = bottomMargin
        
        UIView.animate(withDuration: 0.25) {
            [ self.spacer1, self.separator, self.spacer2, self.userPublicKeyLabel, self.spacer3, self.buttonContainer ].forEach {
                $0.alpha = 1
                $0.isHidden = false
            }
            self.nextButton.alpha = (self.publicKeyTextView.text.isEmpty ? 0 : 1)
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - Interaction
    
    @objc private func copyPublicKey() {
        UIPasteboard.general.string = getUserHexEncodedPublicKey()
        
        copyButton.isUserInteractionEnabled = false
        
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle("copied".localized(), for: .normal)
        }, completion: nil)
        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(enableCopyButton), userInfo: nil, repeats: false)
    }
    
    @objc private func sharePublicKey() {
        let shareVC = UIActivityViewController(activityItems: [ getUserHexEncodedPublicKey() ], applicationActivities: nil)
        
        if UIDevice.current.isIPad {
            shareVC.excludedActivityTypes = []
            shareVC.popoverPresentationController?.permittedArrowDirections = []
            shareVC.popoverPresentationController?.sourceView = self.view
            shareVC.popoverPresentationController?.sourceRect = self.view.bounds
        }
        
        NewDMVC.navigationController!.present(shareVC, animated: true, completion: nil)
    }
    
    @objc fileprivate func startNewDMIfPossible() {
        let text = publicKeyTextView.text?.trimmingCharacters(in: .whitespaces) ?? ""
        NewDMVC.startNewDMIfPossible(with: text)
    }
}

// MARK: - ScanQRCodePlaceholderVC

private final class ScanQRCodePlaceholderVC: UIViewController {
    weak var newDMVC: NewDMVC!
    
    override func viewDidLoad() {
        // Remove background color
        view.themeBackgroundColor = .clear
        
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = "vc_scan_qr_code_camera_access_explanation".localized()
        explanationLabel.themeTextColor = .textPrimary
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.numberOfLines = 0
        
        // Set up call to action button
        let callToActionButton = UIButton()
        callToActionButton.titleLabel?.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        callToActionButton.setTitle("vc_scan_qr_code_grant_camera_access_button_title".localized(), for: UIControl.State.normal)
        callToActionButton.setThemeTitleColor(.primary, for: .normal)
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
        Permissions.requestLibraryPermissionIfNeeded { [weak self] in
            self?.newDMVC.handleCameraAccessGranted()
        }
    }
}

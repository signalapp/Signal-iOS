// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import Curve25519Kit
import SessionMessagingKit
import SessionUtilitiesKit

final class NewDMVC : BaseVC, UIPageViewControllerDataSource, UIPageViewControllerDelegate, OWSQRScannerDelegate {
    private var shouldShowBackButton: Bool = true
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
        result.NewDMVC = self
        return result
    }()
    
    private lazy var scanQRCodePlaceholderVC: ScanQRCodePlaceholderVC = {
        let result = ScanQRCodePlaceholderVC()
        result.NewDMVC = self
        return result
    }()
    
    private lazy var scanQRCodeWrapperVC: ScanQRCodeWrapperVC = {
        let result = ScanQRCodeWrapperVC(message: nil)
        result.delegate = self
        return result
    }()
    
    init(shouldShowBackButton: Bool) {
        self.shouldShowBackButton = shouldShowBackButton
        super.init(nibName: nil, bundle: nil)
    }
    
    init(sessionID: String, shouldShowBackButton: Bool = true) {
        self.shouldShowBackButton = shouldShowBackButton
        super.init(nibName: nil, bundle: nil)
        enterPublicKeyVC.setSessionID(to: sessionID)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override init(nibName: String?, bundle: Bundle?) {
        super.init(nibName: nibName, bundle: bundle)
    }
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle(NSLocalizedString("vc_create_private_chat_title", comment: ""))
        let navigationBar = navigationController!.navigationBar
        // Set up navigation bar buttons
        if !shouldShowBackButton {
            let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
            closeButton.tintColor = Colors.text
            navigationItem.leftBarButtonItem = closeButton
        }
        // Set up page VC
        let hasCameraAccess = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        pages = [ enterPublicKeyVC, (hasCameraAccess ? scanQRCodeWrapperVC : scanQRCodePlaceholderVC) ]
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.setViewControllers([ enterPublicKeyVC ], direction: .forward, animated: false, completion: nil)
        // Set up tab bar
        view.addSubview(tabBar)
        tabBar.pin(.leading, to: .leading, of: view)
        tabBar.pin(.top, to: .top, of: view)
        tabBar.pin(.trailing, to: .trailing, of: view)
        // Set up page VC constraints
        let pageVCView = pageVC.view!
        view.addSubview(pageVCView)
        pageVCView.pin(.leading, to: .leading, of: view)
        pageVCView.pin(.top, to: .bottom, of: tabBar)
        pageVCView.pin(.trailing, to: .trailing, of: view)
        pageVCView.pin(.bottom, to: .bottom, of: view)
        let height: CGFloat = (navigationController!.view.bounds.height - navigationBar.height() - TabBar.snHeight)
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
        startNewDMIfPossible(with: hexEncodedPublicKey)
    }
    
    fileprivate func startNewDMIfPossible(with onsNameOrPublicKey: String) {
        let maybeSessionId: SessionId? = SessionId(from: onsNameOrPublicKey)
        
        if ECKeyPair.isValidHexEncodedPublicKey(candidate: onsNameOrPublicKey) && maybeSessionId?.prefix == .standard {
            startNewDM(with: onsNameOrPublicKey)
            return
        }
        
        // This could be an ONS name
        ModalActivityIndicatorViewController.present(fromViewController: navigationController!, canCancel: false) { [weak self] modalActivityIndicator in
            SnodeAPI.getSessionID(for: onsNameOrPublicKey).done { sessionID in
                modalActivityIndicator.dismiss {
                    self?.startNewDM(with: sessionID)
                }
            }.catch { error in
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

private final class EnterPublicKeyVC : UIViewController {
    weak var NewDMVC: NewDMVC!
    private var isKeyboardShowing = false
    private var bottomConstraint: NSLayoutConstraint!
    private let bottomMargin: CGFloat = UIDevice.current.isIPad ? Values.largeSpacing : 0
    
    // MARK: Components
    private lazy var publicKeyTextView: TextView = {
        let result = TextView(placeholder: NSLocalizedString("vc_enter_public_key_text_field_hint", comment: ""))
        result.autocapitalizationType = .none
        return result
    }()
    
    private lazy var copyButton: Button = {
        let result = Button(style: .prominentOutline, size: .medium)
        result.setTitle(NSLocalizedString("copy", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(copyPublicKey), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var userPublicKeyLabel: SRCopyableLabel = {
        let result = SRCopyableLabel()
        result.textColor = Colors.text
        result.font = Fonts.spaceMono(ofSize: Values.mediumFontSize)
        result.numberOfLines = 0
        result.textAlignment = .center
        result.lineBreakMode = .byCharWrapping
        result.text = getUserHexEncodedPublicKey()
        return result
    }()
    
    private lazy var spacer1 = UIView.spacer(withHeight: Values.largeSpacing)
    private lazy var spacer2 = UIView.spacer(withHeight: Values.largeSpacing)
    private lazy var spacer3 = UIView.spacer(withHeight: Values.largeSpacing)
    private lazy var spacer4 = UIView.spacer(withHeight: Values.largeSpacing)
    
    private lazy var separator = Separator(title: NSLocalizedString("your_session_id", comment: ""))
    
    private lazy var qrCodeImageViewContainer: UIView = {
        let result = UIView()
        result.accessibilityLabel = "Your QR code"
        result.isAccessibilityElement = true
        return result
    }()
    
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
    
    private lazy var nextButton: Button = {
        let result = Button(style: .prominentOutline, size: .large)
        result.setTitle(NSLocalizedString("next", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(startNewDMIfPossible), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var nextButtonContainer: UIView = {
        let result = UIView(
            wrapping: nextButton,
            withInsets: UIEdgeInsets(top: 0, leading: 80, bottom: 0, trailing: 80),
            shouldAdaptForIPadWithWidth: Values.iPadButtonWidth
        )
        result.alpha = isKeyboardShowing ? 1 : 0
        result.isHidden = !isKeyboardShowing
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Remove background color
        view.backgroundColor = .clear
        // User session id container
        let userPublicKeyContainer = UIView(
            wrapping: userPublicKeyLabel,
            withInsets: .zero,
            shouldAdaptForIPadWithWidth: Values.iPadUserSessionIdContainerWidth
        )
        // Explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text.withAlphaComponent(Values.mediumOpacity)
        explanationLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        explanationLabel.text = NSLocalizedString("vc_enter_public_key_explanation", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up QR code image view
        let qrCodeImageView = UIImageView()
        let qrCode = QRCode.generate(for: getUserHexEncodedPublicKey(), hasBackground: true)
        qrCodeImageView.image = qrCode
        qrCodeImageView.contentMode = .scaleAspectFit
        qrCodeImageView.set(.height, to: isIPhone5OrSmaller ? 160 : 220)
        qrCodeImageView.set(.width, to: isIPhone5OrSmaller ? 160 : 220)
        qrCodeImageView.layer.cornerRadius = 8
        qrCodeImageView.layer.masksToBounds = true
        // Set up QR code image view container
        qrCodeImageViewContainer.addSubview(qrCodeImageView)
        qrCodeImageView.center(.horizontal, in: qrCodeImageViewContainer)
        qrCodeImageView.pin(.top, to: .top, of: qrCodeImageViewContainer)
        qrCodeImageView.pin(.bottom, to: .bottom, of: qrCodeImageViewContainer)
        // Share button
        let shareButton = Button(style: .prominentOutline, size: .medium)
        shareButton.setTitle(NSLocalizedString("share", comment: ""), for: UIControl.State.normal)
        shareButton.addTarget(self, action: #selector(sharePublicKey), for: UIControl.Event.touchUpInside)
        // Button container
        buttonContainer.addArrangedSubview(copyButton)
        buttonContainer.addArrangedSubview(shareButton)
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [
            publicKeyTextView,
            UIView.spacer(withHeight: Values.smallSpacing),
            explanationLabel,
            spacer1,
            separator,
            spacer2,
            qrCodeImageViewContainer,
            spacer3,
            userPublicKeyContainer,
            spacer4,
            buttonContainer,
            UIView.vStretchingSpacer(),
            nextButtonContainer
        ])
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
    
    // MARK: General
    func setSessionID(to sessionID: String){
        publicKeyTextView.insertText(sessionID)
    }

    func constrainHeight(to height: CGFloat) {
        view.set(.height, to: height)
    }
    
    @objc private func dismissKeyboard() {
        publicKeyTextView.resignFirstResponder()
    }
    
    @objc private func enableCopyButton() {
        copyButton.isUserInteractionEnabled = true
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle(NSLocalizedString("copy", comment: ""), for: UIControl.State.normal)
        }, completion: nil)
    }
    
    // MARK: Updating
    @objc private func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
        guard !isKeyboardShowing else { return }
        isKeyboardShowing = true
        guard let newHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.size.height else { return }
        bottomConstraint.constant = newHeight + bottomMargin
        UIView.animate(withDuration: 0.25) {
            self.nextButtonContainer.alpha = 1
            self.nextButtonContainer.isHidden = false
            [ self.spacer1, self.separator, self.spacer2, self.qrCodeImageViewContainer, self.spacer3, self.userPublicKeyLabel, self.spacer4, self.buttonContainer ].forEach {
                $0.alpha = 0
                $0.isHidden = true
            }
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func handleKeyboardWillHideNotification(_ notification: Notification) {
        guard isKeyboardShowing else { return }
        isKeyboardShowing = false
        bottomConstraint.constant = bottomMargin
        UIView.animate(withDuration: 0.25) {
            self.nextButtonContainer.alpha = 0
            self.nextButtonContainer.isHidden = true
            [ self.spacer1, self.separator, self.spacer2, self.qrCodeImageViewContainer, self.spacer3, self.userPublicKeyLabel, self.spacer4, self.buttonContainer ].forEach {
                $0.alpha = 1
                $0.isHidden = false
            }
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: Interaction
    @objc private func copyPublicKey() {
        UIPasteboard.general.string = getUserHexEncodedPublicKey()
        copyButton.isUserInteractionEnabled = false
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle(NSLocalizedString("copied", comment: ""), for: UIControl.State.normal)
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

private final class ScanQRCodePlaceholderVC : UIViewController {
    weak var NewDMVC: NewDMVC!
    
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
                self?.NewDMVC.handleCameraAccessGranted()
            } else {
                // Do nothing
            }
        })
    }
}

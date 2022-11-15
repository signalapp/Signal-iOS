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
    private var shouldShowBackButton: Bool = true
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
        let result: ScanQRCodePlaceholderVC = ScanQRCodePlaceholderVC()
        result.newDMVC = self
        
        return result
    }()
    
    private lazy var scanQRCodeWrapperVC: ScanQRCodeWrapperVC = {
        let result: ScanQRCodeWrapperVC = ScanQRCodeWrapperVC(message: nil)
        result.delegate = self
        
        return result
    }()
    
    // MARK: - Initialization
    
    init(sessionId: String? = nil, shouldShowBackButton: Bool = true) {
        self.shouldShowBackButton = shouldShowBackButton
        
        super.init(nibName: nil, bundle: nil)
        
        if let sessionId: String = sessionId {
            enterPublicKeyVC.setSessionId(to: sessionId)
        }
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
        view.themeBackgroundColor = .newConversation_background
        
        // Set up navigation bar buttons
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.themeTintColor = .textPrimary
        
        if shouldShowBackButton {
            navigationItem.rightBarButtonItem = closeButton
        }
        else {
            navigationItem.leftBarButtonItem = closeButton
        }
        
        // Page VC
        let hasCameraAccess = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        pages = [ enterPublicKeyVC, (hasCameraAccess ? scanQRCodeWrapperVC : scanQRCodePlaceholderVC) ]
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.setViewControllers([ enterPublicKeyVC ], direction: .forward, animated: false, completion: nil)
        
        // Tab bar
        view.addSubview(tabBar)
        tabBar.pin(.top, to: .top, of: view)
        tabBar.pin(.leading, to: .leading, of: view)
        tabBar.pin(.trailing, to: .trailing, of: view)
        
        // Page VC constraints
        let pageVCView = pageVC.view!
        view.addSubview(pageVCView)
        pageVCView.pin(.leading, to: .leading, of: view)
        pageVCView.pin(.top, to: .bottom, of: tabBar)
        pageVCView.pin(.trailing, to: .trailing, of: view)
        pageVCView.pin(.bottom, to: .bottom, of: view)
        
        let navBarHeight: CGFloat = (navigationController?.navigationBar.frame.size.height ?? 0)
        let statusBarHeight: CGFloat = UIApplication.shared.statusBarFrame.size.height
        let height: CGFloat = ((navigationController?.view.bounds.height ?? 0) - navBarHeight - TabBar.snHeight - statusBarHeight)
        let size: CGSize = CGSize(width: UIScreen.main.bounds.width, height: height)
        enterPublicKeyVC.constrainSize(to: size)
        scanQRCodePlaceholderVC.constrainSize(to: size)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let height: CGFloat = (size.height - TabBar.snHeight)
        let size: CGSize = CGSize(width: size.width, height: height)
        enterPublicKeyVC.constrainSize(to: size)
        scanQRCodePlaceholderVC.constrainSize(to: size)
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
        DispatchQueue.main.async {
            self.pages[1] = self.scanQRCodeWrapperVC
            self.pageVC.setViewControllers([ self.scanQRCodeWrapperVC ], direction: .forward, animated: false, completion: nil)
        }
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
                                    "DM_ERROR_DIRECT_BLINDED_ID".localized() :
                                    "DM_ERROR_INVALID".localized()
                                )
                            }()
                            
                            let modal: ConfirmationModal = ConfirmationModal(
                                targetView: self?.view,
                                info: ConfirmationModal.Info(
                                    title: "ALERT_ERROR_TITLE".localized(),
                                    explanation: message,
                                    cancelTitle: "BUTTON_OK".localized(),
                                    cancelStyle: .alert_text
                                )
                            )
                            self?.present(modal, animated: true)
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
        let result = TextView(placeholder: "vc_enter_public_key_text_field_hint".localized()) { [weak self] text in
            self?.nextButton.isEnabled = !text.isEmpty
        }
        result.autocapitalizationType = .none
        
        return result
    }()
    
    private lazy var explanationLabel: UILabel = {
        let result: UILabel = UILabel()
        result.setContentHuggingPriority(.required, for: .vertical)
        result.setContentCompressionResistancePriority(.required, for: .vertical)
        result.font = .systemFont(ofSize: Values.verySmallFontSize)
        result.text = "vc_enter_public_key_explanation".localized()
        result.themeTextColor = .textSecondary
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        result.numberOfLines = 0
        
        return result
    }()
    
    private lazy var spacer1 = UIView.spacer(withHeight: Values.largeSpacing)
    private lazy var spacer2 = UIView.spacer(withHeight: Values.largeSpacing)
    private lazy var spacer3 = UIView.spacer(withHeight: Values.largeSpacing)
    private lazy var spacer4 = UIView.spacer(withHeight: Values.largeSpacing)
    
    private lazy var separator = Separator(title: "your_session_id".localized())
    
    private lazy var qrCodeView: UIView = {
        let result: UIView = UIView()
        result.layer.cornerRadius = 8
        
        let qrCodeImageView: UIImageView = UIImageView()
        qrCodeImageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        qrCodeImageView.image = QRCode.generate(for: getUserHexEncodedPublicKey(), hasBackground: false)
            .withRenderingMode(.alwaysTemplate)
        qrCodeImageView.set(.width, to: .height, of: qrCodeImageView)
        qrCodeImageView.heightAnchor
            .constraint(lessThanOrEqualToConstant: (isIPhone5OrSmaller ? 160 : 220))
            .isActive = true

#if targetEnvironment(simulator)
#else
        // Note: For some reason setting this seems to stop the QRCode from rendering on the
        // simulator so only doing it on device
        qrCodeImageView.contentMode = .scaleAspectFit
#endif
        
        result.addSubview(qrCodeImageView)
        qrCodeImageView.pin(
            to: result,
            withInset: 5    // The QRCode image has about 6pt of padding and we want 11 in total
        )
        
        ThemeManager.onThemeChange(observer: qrCodeImageView) { [weak qrCodeImageView, weak result] theme, _ in
            switch theme.interfaceStyle {
                case .light:
                    qrCodeImageView?.themeTintColorForced = .theme(theme, color: .textPrimary)
                    result?.themeBackgroundColorForced = nil

                default:
                    qrCodeImageView?.themeTintColorForced = .theme(theme, color: .backgroundPrimary)
                    result?.themeBackgroundColorForced = .color(.white)
            }

        }
        
        return result
    }()
    
    private lazy var qrCodeImageViewContainer: UIView = {
        let result: UIView = UIView()
        result.accessibilityLabel = "Your QR code"
        result.isAccessibilityElement = true
        result.addSubview(qrCodeView)
        qrCodeView.center(.horizontal, in: result)
        qrCodeView.pin(.top, to: .top, of: result)
        qrCodeView.pin(.bottom, to: .bottom, of: result)
        
        return result
    }()
    
    private lazy var userPublicKeyLabel: SRCopyableLabel = {
        let result: SRCopyableLabel = SRCopyableLabel()
        result.setContentCompressionResistancePriority(.required, for: .vertical)
        result.font = Fonts.spaceMono(ofSize: Values.mediumFontSize)
        result.text = getUserHexEncodedPublicKey()
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        result.lineBreakMode = .byCharWrapping
        result.numberOfLines = 0
        
        return result
    }()
    
    private lazy var userPublicKeyContainer: UIView = {
        let result: UIView = UIView(
            wrapping: userPublicKeyLabel,
            withInsets: .zero,
            shouldAdaptForIPadWithWidth: Values.iPadUserSessionIdContainerWidth
        )
        
        return result
    }()
    
    private lazy var buttonContainer: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ copyButton, shareButton ])
        result.axis = .horizontal
        result.spacing = UIDevice.current.isIPad ? Values.iPadButtonSpacing : Values.mediumSpacing
        result.distribution = .fillEqually
        
        if (UIDevice.current.isIPad) {
            result.layoutMargins = UIEdgeInsets(top: 0, left: Values.iPadButtonContainerMargin, bottom: 0, right: Values.iPadButtonContainerMargin)
            result.isLayoutMarginsRelativeArrangement = true
        }
        
        return result
    }()
    
    private lazy var copyButton: SessionButton = {
        let result = SessionButton(style: .bordered, size: .small)
        result.setTitle("copy".localized(), for: .normal)
        result.addTarget(self, action: #selector(copyPublicKey), for: .touchUpInside)
        
        return result
    }()
    
    private lazy var shareButton: SessionButton = {
        let result = SessionButton(style: .bordered, size: .small)
        result.setTitle("share".localized(), for: .normal)
        result.addTarget(self, action: #selector(sharePublicKey), for: .touchUpInside)
        
        return result
    }()
    
    private lazy var nextButtonContainer: UIView = {
        let result = UIView(
            wrapping: nextButton,
            withInsets: UIEdgeInsets(top: 0, leading: 80, bottom: 0, trailing: 80),
            shouldAdaptForIPadWithWidth: Values.iPadButtonWidth
        )
        result.alpha = (isKeyboardShowing ? 1 : 0)
        result.isHidden = !isKeyboardShowing
        
        return result
    }()
    
    private lazy var nextButton: SessionButton = {
        let result = SessionButton(style: .bordered, size: .large)
        result.setTitle("next".localized(), for: .normal)
        result.isEnabled = false
        result.addTarget(self, action: #selector(startNewDMIfPossible), for: .touchUpInside)
        
        return result
    }()
    
    private var viewWidth: NSLayoutConstraint?
    private var viewHeight: NSLayoutConstraint?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        // Remove background color
        view.themeBackgroundColor = .clear
        
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
        mainStackView.layoutMargins = UIEdgeInsets(
            top: Values.largeSpacing,
            left: Values.largeSpacing,
            bottom: Values.smallSpacing,
            right: Values.largeSpacing
        )
        mainStackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(mainStackView)

        mainStackView.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing, UIView.VerticalEdge.top ], to: view)
        bottomConstraint = mainStackView.pin(.bottom, to: .bottom, of: view, withInset: bottomMargin)

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
    
    func constrainSize(to size: CGSize) {
        if viewWidth == nil {
            viewWidth = view.set(.width, to: size.width)
        } else {
            viewWidth?.constant = size.width
        }
        
        if viewHeight == nil {
            viewHeight = view.set(.height, to: size.height)
        } else {
            viewHeight?.constant = size.height
        }
    }

    
    func setSessionId(to sessionId: String) {
        publicKeyTextView.insertText(sessionId)
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
        
        let duration = max(0.25, ((notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0))
        let viewsToHide: [UIView] = [ self.spacer1, self.separator, self.spacer2, self.qrCodeImageViewContainer, self.spacer3, self.userPublicKeyContainer, self.spacer4, self.buttonContainer ]
        
        // We dispatch to the next run loop to prevent the animation getting stuck within the
        // keyboard appearance animation (which would make the second animation start once the
        // keyboard finishes appearing)
        DispatchQueue.main.async {
            UIView.animate(
                withDuration: (duration / 2),
                delay: 0,
                options: .curveEaseOut,
                animations: {
                    viewsToHide.forEach { $0.alpha = 0 }
                },
                completion: { [weak self] _ in
                    UIView.performWithoutAnimation {
                        viewsToHide.forEach { $0.isHidden = true }
                        
                        self?.nextButtonContainer.alpha = 0
                        self?.nextButtonContainer.isHidden = false
                        self?.bottomConstraint.constant = -(newHeight + (self?.bottomMargin ?? 0))
                        self?.view.layoutIfNeeded()
                    }
                    
                    UIView.animate(
                        withDuration: (duration / 2),
                        delay: 0,
                        options: .curveEaseIn,
                        animations: {
                            self?.nextButtonContainer.alpha = 1
                        },
                        completion: nil
                    )
                }
            )
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
        
        let duration = max(0.25, ((notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0))
        let viewsToShow: [UIView] = [ self.spacer1, self.separator, self.spacer2, self.qrCodeImageViewContainer, self.spacer3, self.userPublicKeyContainer, self.spacer4, self.buttonContainer ]
        isKeyboardShowing = false
        
        // We dispatch to the next run loop to prevent the animation getting stuck within the
        // keyboard hide animation (which would make the second animation start once the keyboard
        // finishes disappearing)
        DispatchQueue.main.async {
            UIView.animate(
                withDuration: (duration / 2),
                delay: 0,
                options: .curveEaseOut,
                animations: { [weak self] in
                    self?.nextButtonContainer.alpha = 0
                },
                completion: { [weak self] _ in
                    UIView.performWithoutAnimation {
                        viewsToShow.forEach {
                            $0.alpha = 0
                            $0.isHidden = false
                        }
                        
                        self?.nextButtonContainer.isHidden = true
                        self?.bottomConstraint.constant = -(self?.bottomMargin ?? 0)
                        self?.view.layoutIfNeeded()
                    }
                    
                    UIView.animate(
                        withDuration: (duration / 2),
                        delay: 0,
                        options: .curveEaseIn,
                        animations: {
                            viewsToShow.forEach { $0.alpha = 1 }
                        },
                        completion: nil
                    )
                }
            )
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
    
    private var viewWidth: NSLayoutConstraint?
    private var viewHeight: NSLayoutConstraint?
    
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
        view.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: view, withInset: Values.massiveSpacing)
        view.pin(.trailing, to: .trailing, of: stackView, withInset: Values.massiveSpacing)
        
        let verticalCenteringConstraint = stackView.center(.vertical, in: view)
        verticalCenteringConstraint.constant = -16 // Makes things appear centered visually
    }
    
    func constrainSize(to size: CGSize) {
        if viewWidth == nil {
            viewWidth = view.set(.width, to: size.width)
        } else {
            viewWidth?.constant = size.width
        }
        
        if viewHeight == nil {
            viewHeight = view.set(.height, to: size.height)
        } else {
            viewHeight?.constant = size.height
        }
    }

    
    @objc private func requestCameraAccess() {
        Permissions.requestCameraPermissionIfNeeded { [weak self] in
            self?.newDMVC.handleCameraAccessGranted()
        }
    }
}

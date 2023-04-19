//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

@objc
public class StickerPackViewController: OWSViewController {

    // MARK: Properties

    private let stickerPackInfo: StickerPackInfo

    private let stickerCollectionView = StickerPackCollectionView(placeholderColor: .ows_blackAlpha60)

    private let dataSource: StickerPackDataSource

    // MARK: Initializers

    @objc
    public required init(stickerPackInfo: StickerPackInfo) {
        self.stickerPackInfo = stickerPackInfo
        self.dataSource = TransientStickerPackDataSource(stickerPackInfo: stickerPackInfo,
                                                         shouldDownloadAllStickers: true)

        super.init()

        stickerCollectionView.stickerDelegate = self
        stickerCollectionView.show(dataSource: dataSource)
        dataSource.add(delegate: self)

        NotificationCenter.default.addObserver(self, selector: #selector(didChangeStatusBarFrame), name: UIApplication.didChangeStatusBarFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.stickersOrPacksDidChange,
                                               object: nil)
    }

    // MARK: - View Lifecycle

    override public var canBecomeFirstResponder: Bool {
        return true
    }

    @objc
    public func present(from fromViewController: UIViewController,
                        animated: Bool) {
        AssertIsOnMainThread()

        if #available(iOS 13, *) {
            // iOS 13 on the iOS 13 SDK handles the modal blur correctly.
            fromViewController.presentFormSheet(self, animated: animated) {
                // ensure any presented keyboard is dismissed, this seems to be
                // an issue only when opening signal from a universal link in
                // an external app
                self.becomeFirstResponder()
            }
            return
        }

        // Pre-iOS 13, or without the iOS 13 SDK, we need to manually setup the
        // form sheet in order to allow it to blur and show through the background.

        modalPresentationStyle = .custom
        transitioningDelegate = self
        fromViewController.present(self, animated: animated) {
            // ensure any presented keyboard is dismissed, this seems to be
            // an issue only when opening signal from a universal link in
            // an external app
            self.becomeFirstResponder()
        }
    }

    override public func loadView() {
        view = UIView()

        if UIAccessibility.isReduceTransparencyEnabled {
            view.backgroundColor = Theme.darkThemeBackgroundColor
        } else {
            view.backgroundColor = .clear
            view.isOpaque = false

            // Unlike Theme.barBlurEffect, we use light blur in dark theme
            // and dark blur in light theme.
            let blurEffect = UIBlurEffect(style: Theme.isDarkThemeEnabled ? .light : .dark)
            let blurEffectView = UIVisualEffectView(effect: blurEffect)
            view.addSubview(blurEffectView)
            blurEffectView.autoPinEdgesToSuperviewEdges()
        }

        let hMargin: CGFloat = 16

        dismissButton.setTemplateImageName("x-24", tintColor: Theme.darkThemePrimaryColor)
        dismissButton.addTarget(self, action: #selector(dismissButtonPressed(sender:)), for: .touchUpInside)
        dismissButton.contentEdgeInsets = UIEdgeInsets(top: 20, leading: hMargin, bottom: 20, trailing: hMargin)
        dismissButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "dismissButton")

        coverView.autoSetDimensions(to: CGSize(square: 64))
        coverView.setCompressionResistanceHigh()
        coverView.setContentHuggingHigh()

        titleLabel.textColor = Theme.darkThemePrimaryColor
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.font = UIFont.dynamicTypeTitle1.semibold()

        authorLabel.font = UIFont.dynamicTypeBody

        defaultPackIconView.setTemplateImageName("check-circle-filled-16", tintColor: Theme.accentBlueColor)
        defaultPackIconView.isHidden = true

        shareButton.setTemplateImageName("forward-solid-24", tintColor: Theme.darkThemePrimaryColor)
        shareButton.addTarget(self, action: #selector(shareButtonPressed(sender:)), for: .touchUpInside)
        shareButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "shareButton")

        view.addSubview(dismissButton)
        dismissButton.autoPinEdge(toSuperviewEdge: .leading)
        dismissButton.autoPinEdge(toSuperviewSafeArea: .top)

        let bottomRowView = UIStackView(arrangedSubviews: [ defaultPackIconView, authorLabel ])
        bottomRowView.axis = .horizontal
        bottomRowView.alignment = .center
        bottomRowView.spacing = 5
        defaultPackIconView.setCompressionResistanceHigh()
        defaultPackIconView.setContentHuggingHigh()

        let textRowsView = UIStackView(arrangedSubviews: [ titleLabel, bottomRowView ])
        textRowsView.axis = .vertical
        textRowsView.alignment = .leading

        let headerStack = UIStackView(arrangedSubviews: [ coverView, textRowsView, shareButton ])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 10
        headerStack.layoutMargins = UIEdgeInsets(top: 10, leading: hMargin, bottom: 10, trailing: hMargin)
        headerStack.isLayoutMarginsRelativeArrangement = true
        textRowsView.setCompressionResistanceHorizontalLow()
        textRowsView.setContentHuggingHorizontalLow()

        view.addSubview(headerStack)
        headerStack.autoPinEdge(.top, to: .bottom, of: dismissButton)
        headerStack.autoPinWidthToSuperview()

        stickerCollectionView.backgroundColor = .clear
        view.addSubview(stickerCollectionView)
        stickerCollectionView.autoPinWidthToSuperview()
        stickerCollectionView.autoPinEdge(.top, to: .bottom, of: headerStack)

        let installButton = OWSFlatButton.button(title: NSLocalizedString("STICKERS_INSTALL_BUTTON", comment: "Label for the 'install sticker pack' button."),
                                             font: UIFont.dynamicTypeBody.semibold(),
                                             titleColor: Theme.accentBlueColor,
                                             backgroundColor: UIColor.white,
                                             target: self,
                                             selector: #selector(didTapInstall))
        self.installButton = installButton
        installButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "installButton")
        let uninstallButton = OWSFlatButton.button(title: NSLocalizedString("STICKERS_UNINSTALL_BUTTON", comment: "Label for the 'uninstall sticker pack' button."),
                                             font: UIFont.dynamicTypeBody.semibold(),
                                             titleColor: Theme.accentBlueColor,
                                             backgroundColor: UIColor.white,
                                             target: self,
                                             selector: #selector(didTapUninstall))
        self.uninstallButton = uninstallButton
        uninstallButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "uninstallButton")
        for button in [installButton, uninstallButton] {
            view.addSubview(button)
            button.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 10)
            button.autoPinEdge(.top, to: .bottom, of: stickerCollectionView)
            button.autoPinWidthToSuperview(withMargin: hMargin)
            button.autoSetHeightUsingFont()
        }

        view.addSubview(loadingIndicator)
        loadingIndicator.autoCenterInSuperview()

        loadFailedLabel.text = NSLocalizedString("STICKERS_PACK_VIEW_FAILED_TO_LOAD",
                                                 comment: "Label indicating that the sticker pack failed to load.")
        loadFailedLabel.font = UIFont.dynamicTypeBody
        loadFailedLabel.textColor = Theme.darkThemePrimaryColor
        loadFailedLabel.textAlignment = .center
        loadFailedLabel.numberOfLines = 0
        loadFailedLabel.lineBreakMode = .byWordWrapping
        view.addSubview(loadFailedLabel)
        loadFailedLabel.autoPinWidthToSuperview(withMargin: hMargin)
        loadFailedLabel.autoVCenterInSuperview()

        updateContent()

        loadTimer = WeakTimer.scheduledTimer(timeInterval: 1, target: self, userInfo: nil, repeats: false) { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            strongSelf.loadTimerHasFired = true
            strongSelf.loadTimer?.invalidate()
            strongSelf.loadTimer = nil
            strongSelf.updateContent()
        }
    }

    private let dismissButton = UIButton()
    private let coverView = StickerReusableView()
    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    private let defaultPackIconView = UIImageView()
    private let shareButton = UIButton()
    private var installButton: OWSFlatButton?
    private var uninstallButton: OWSFlatButton?
    private var loadingIndicator = UIActivityIndicatorView(style: .whiteLarge)
    private var loadFailedLabel = UILabel()
    // We use this timer to ensure that we don't show the
    // loading indicator for N seconds, to prevent a "flash"
    // when presenting the view.
    private var loadTimer: Timer?
    private var loadTimerHasFired = false

    private func updateContent() {
        guard !isDismissing else { return }

        updateCover()
        updateInsets()

        guard let stickerPack = dataSource.getStickerPack() else {
            installButton?.isHidden = true
            uninstallButton?.isHidden = true
            shareButton.isHidden = true

            if StickerManager.isStickerPackMissing(stickerPackInfo: stickerPackInfo) {
                loadFailedLabel.isHidden = false
                loadingIndicator.isHidden = true
                loadingIndicator.stopAnimating()
            } else if loadTimerHasFired {
                loadFailedLabel.isHidden = true
                loadingIndicator.isHidden = false
                loadingIndicator.startAnimating()
            } else {
                loadFailedLabel.isHidden = true
                loadingIndicator.isHidden = true
                loadingIndicator.stopAnimating()
            }
            return
        }

        let defaultTitle = NSLocalizedString("STICKERS_PACK_VIEW_DEFAULT_TITLE", comment: "The default title for the 'sticker pack' view.")
        if let title = stickerPack.title?.ows_stripped(), !title.isEmpty {
            titleLabel.text = title.filterForDisplay
        } else {
            titleLabel.text = defaultTitle
        }

        authorLabel.text = stickerPack.author?.filterForDisplay

        let isDefaultStickerPack = StickerManager.isDefaultStickerPack(packId: stickerPack.info.packId)
        authorLabel.textColor = isDefaultStickerPack ? Theme.accentBlueColor : Theme.darkThemePrimaryColor
        defaultPackIconView.isHidden = !isDefaultStickerPack

        // We need to consult StickerManager for the latest "isInstalled"
        // state, since the data source may be caching stale state.
        let isInstalled = StickerManager.isStickerPackInstalled(stickerPackInfo: stickerPack.info)
        installButton?.isHidden = isInstalled
        uninstallButton?.isHidden = !isInstalled
        shareButton.isHidden = false
        loadFailedLabel.isHidden = true
        loadingIndicator.isHidden = true
        loadingIndicator.stopAnimating()
    }

    private func updateCover() {
        guard !coverView.hasStickerView else { return }

        guard let stickerPack = dataSource.getStickerPack() else { return }
        let coverInfo = stickerPack.coverInfo
        guard let stickerView = StickerView.stickerView(
            forStickerInfo: coverInfo,
            dataSource: dataSource
        ) else {
            coverView.showPlaceholder(color: .ows_blackAlpha60)
            return
        }

        coverView.configure(with: stickerView)
    }

    private func updateInsets() {
        UIView.setAnimationsEnabled(false)

        if !CurrentAppContext().isMainApp {
            self.additionalSafeAreaInsets = .zero
        } else if CurrentAppContext().hasActiveCall {
            self.additionalSafeAreaInsets = UIEdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0)
        } else {
            self.additionalSafeAreaInsets = .zero
        }

        UIView.setAnimationsEnabled(true)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        StickerManager.refreshContents()
    }

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    // - MARK: Events

    private var isDismissing = false

    @objc
    private func didTapInstall(sender: UIButton) {
        AssertIsOnMainThread()

        Logger.verbose("")

        isDismissing = true

        guard let stickerPack = dataSource.getStickerPack() else {
            owsFailDebug("Missing sticker pack.")
            return
        }

        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false,
                                                     presentationDelay: 0) { modal in

                                                        self.databaseStorage.write { (transaction) in
                                                            StickerManager.installStickerPack(stickerPack: stickerPack,
                                                                                              wasLocallyInitiated: true,
                                                                                              transaction: transaction)
                                                            transaction.addAsyncCompletionOnMain {
                                                                modal.dismiss {
                                                                    self.dismiss(animated: true)
                                                                }
                                                            }
                                                        }
        }
    }

    @objc
    private func didTapUninstall(sender: UIButton) {
        AssertIsOnMainThread()

        Logger.verbose("")

        isDismissing = true

        let stickerPackInfo = self.stickerPackInfo
        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false,
                                                     presentationDelay: 0) { modal in

                                                        self.databaseStorage.write { (transaction) in
                                                            StickerManager.uninstallStickerPack(stickerPackInfo: stickerPackInfo,
                                                                                                wasLocallyInitiated: true,
                                                                                                transaction: transaction)
                                                            transaction.addAsyncCompletionOnMain {
                                                                modal.dismiss {
                                                                    self.dismiss(animated: true)
                                                                }
                                                            }
                                                        }
        }
    }

    @objc
    private func dismissButtonPressed(sender: UIButton) {
        AssertIsOnMainThread()

        isDismissing = true

        dismiss(animated: true)
    }

    // We need to retain a link to the send flow during the send flow.
    private var sendMessageFlow: SendMessageFlow?

    @objc
    func shareButtonPressed(sender: UIButton) {
        AssertIsOnMainThread()

        guard let stickerPack = dataSource.getStickerPack() else {
            owsFailDebug("Missing sticker pack.")
            return
        }
        let packUrl = stickerPack.info.shareUrl()

        let navigationController = OWSNavigationController()
        let messageBody = MessageBody(text: packUrl, ranges: .empty)
        let unapprovedContent = SendMessageUnapprovedContent.text(messageBody: messageBody)
        let sendMessageFlow = SendMessageFlow(flowType: .`default`,
                                              unapprovedContent: unapprovedContent,
                                              useConversationComposeForSingleRecipient: true,
                                              navigationController: navigationController,
                                              delegate: self)
        // Retain the flow until it is complete.
        self.sendMessageFlow = sendMessageFlow

        present(navigationController, animated: true)
    }

    @objc
    public func didChangeStatusBarFrame() {
        Logger.debug("")

        updateContent()
    }

    @objc
    func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        Logger.verbose("")

        updateContent()
    }
}

// MARK: -

private class StickerPackViewControllerAnimationController: UIPresentationController {

    let backdropView: UIView = UIView()

    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
        backdropView.backgroundColor = Theme.backdropColor
    }

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView else { return }
        backdropView.alpha = 0
        containerView.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView.alpha = 1
        }, completion: nil)
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView.alpha = 0
        }, completion: { _ in
            self.backdropView.removeFromSuperview()
        })
    }

    var isFullScreen: Bool {
        guard let containerSize = containerView?.frame.size else { return true }
        guard UIDevice.current.isIPad, containerSize.width > (max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) / 2) - 5 else { return true }
        return false
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        var frame = super.frameOfPresentedViewInContainerView
        let containerSize = frame.size

        if !isFullScreen {
            frame.size = CGSize(width: 540, height: 620)
            frame.origin = CGPoint(x: containerSize.width / 2 - frame.size.width / 2, y: containerSize.height / 2 - frame.size.height / 2)
        }

        return frame
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        presentedView?.frame = frameOfPresentedViewInContainerView

        if isFullScreen {
            presentedView?.clipsToBounds = false
            presentedView?.layer.cornerRadius = 0
        } else {
            presentedView?.clipsToBounds = true
            presentedView?.layer.cornerRadius = 13
        }
    }
}

extension StickerPackViewController: UIViewControllerTransitioningDelegate {
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return StickerPackViewControllerAnimationController(presentedViewController: presented, presenting: presenting)
    }
}

// MARK: -

extension StickerPackViewController: StickerPackDataSourceDelegate {
    public func stickerPackDataDidChange() {
        AssertIsOnMainThread()

        updateContent()
    }
}

// MARK: -

extension StickerPackViewController: StickerPackCollectionViewDelegate {
    public func didTapSticker(stickerInfo: StickerInfo) {
        AssertIsOnMainThread()

        Logger.verbose("")
    }

    public func stickerPreviewHostView() -> UIView? {
        AssertIsOnMainThread()

        return view
    }

    public func stickerPreviewHasOverlay() -> Bool {
        return true
    }
}

// MARK: -

extension StickerPackViewController: SendMessageDelegate {

    public func sendMessageFlowDidComplete(threads: [TSThread]) {
        AssertIsOnMainThread()

        sendMessageFlow = nil

        dismiss(animated: true)
    }

    public func sendMessageFlowDidCancel() {
        AssertIsOnMainThread()

        sendMessageFlow = nil

        dismiss(animated: true)
    }
}

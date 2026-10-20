//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class StickerPackViewController: OWSViewController, StickerPackDataSourceDelegate, StickerPackCollectionViewDelegate,
    SendMessageDelegate,
    OWSNavigationChildController
{

    // MARK: Properties

    private let stickerPackInfo: StickerPackInfo
    private let dataSource: StickerPackDataSource
    private let db: DB

    private var sendStickerFlow: SendStickerFlow?

    // MARK: UIViewController

    convenience init(stickerPackInfo: StickerPackInfo) {
        self.init(
            stickerPackInfo: stickerPackInfo,
            db: DependenciesBridge.shared.db,
        )
    }

    init(
        stickerPackInfo: StickerPackInfo,
        db: DB,
    ) {
        self.stickerPackInfo = stickerPackInfo
        self.db = db
        self.dataSource = TransientStickerPackDataSource(
            stickerPackInfo: stickerPackInfo,
            shouldDownloadAllStickers: true,
        )

        super.init()

        stickerCollectionView.stickerDelegate = self
        stickerCollectionView.show(dataSource: dataSource)
        dataSource.add(delegate: self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stickersOrPacksDidChange),
            name: StickerManager.stickersOrPacksDidChange,
            object: nil,
        )
    }

    var navbarBackgroundColorOverride: UIColor? {
        .Signal.secondaryBackground
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.secondaryBackground

        let titleView = UIStackView(arrangedSubviews: [navBarTitleLabel, navBarDefaultPackImage])
        titleView.spacing = 4
        titleView.axis = .horizontal
        titleView.alignment = .center
        navigationItem.titleView = titleView
        navigationItem.leftBarButtonItem = .closeButton { [weak self] in
            self?.dismissButtonPressed()
        }

        navBarDefaultPackImage.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            navBarDefaultPackImage.widthAnchor.constraint(equalToConstant: 17),
            navBarDefaultPackImage.heightAnchor.constraint(equalToConstant: 17),
        ])

        stickerCollectionView.registerStickerPackHeaderAndSetConfigure { [weak self] header in
            guard let self else { return }
            guard let stickerPack = self.dataSource.getStickerPack() else {
                header.setContentHidden(true)
                return
            }
            let isInstalled = StickerManager.isStickerPackInstalled(stickerPackInfo: stickerPack.info)
            header.configure(
                stickerPack: stickerPack,
                dataSource: self.dataSource,
                stickerCount: self.stickerCollectionView.stickerCount,
                isInstalled: isInstalled,
                onTapSend: { [weak self] in self?.shareButtonPressed() },
                onTapLink: { [weak self] in self?.linkButtonPressed() },
                onTapUninstall: { [weak self] in self?.didTapUninstall() },
            )
        }

        // Hide the title in the nav bar until the user scrolls
        navigationItem.titleView?.alpha = 0
        contentOffsetObservation = stickerCollectionView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            self?.updateNavigationTitleVisibility()
        }

        view.addSubview(stickerCollectionView)
        view.addSubview(bottomButtonContainer)

        stickerCollectionView.translatesAutoresizingMaskIntoConstraints = false
        bottomButtonContainer.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stickerCollectionView.topAnchor.constraint(equalTo: view.topAnchor),
            stickerCollectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stickerCollectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stickerCollectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            bottomButtonContainer.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            bottomButtonContainer.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            bottomButtonContainer.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
        ])

        if #available(iOS 26, *) {
            let bottomEdgeInteraction = UIScrollEdgeElementContainerInteraction()
            bottomEdgeInteraction.edge = .bottom
            bottomEdgeInteraction.scrollView = stickerCollectionView
            bottomButtonContainer.addInteraction(bottomEdgeInteraction)
        }

        // Loading indicator
        loadingIndicator.tintColor = .Signal.label
        view.addSubview(loadingIndicator)

        // "Load Failed" text
        view.addSubview(loadFailedLabel)

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadFailedLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            loadFailedLabel.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor),
            loadFailedLabel.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            loadFailedLabel.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
        ])

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

        let stickerManager = SSKEnvironment.shared.stickerManagerRef
        stickerManager.downloadPendingSickerPacks()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Necessary to set top and bottom content insets.
        DispatchQueue.main.async {
            self.updateCollectionViewContentInset()
        }
    }

    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()

        updateCollectionViewContentInset()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    // MARK: Presentation

    override var canBecomeFirstResponder: Bool {
        return true
    }

    func present(from fromViewController: UIViewController, animated: Bool) {
        AssertIsOnMainThread()

        let navController = OWSNavigationController(rootViewController: self)
        fromViewController.presentFormSheet(navController, animated: animated) {
            // ensure any presented keyboard is dismissed, this seems to be
            // an issue only when opening signal from a universal link in
            // an external app
            self.becomeFirstResponder()
        }
    }

    // MARK: Layout

    private var contentOffsetObservation: NSKeyValueObservation?

    private let navBarTitleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.label
        label.font = .dynamicTypeBody.semibold()
        label.numberOfLines = 1
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
        return label
    }()

    private let navBarDefaultPackImage = UIImageView(image: .official)

    private let stickerCollectionView = StickerPackCollectionView(placeholderColor: .ows_blackAlpha60)

    private func updateCollectionViewContentInset() {
        stickerCollectionView.layoutIfNeeded()

        var contentInset = stickerCollectionView.contentInset

        contentInset.top = 16
        contentInset.bottom = bottomButtonContainer.frame.height + 16

        stickerCollectionView.verticalScrollIndicatorInsets.top = view.safeAreaInsets.top + contentInset.top
        stickerCollectionView.verticalScrollIndicatorInsets.bottom = contentInset.bottom

        contentInset.leading = view.layoutMargins.leading - view.safeAreaInsets.leading
        contentInset.trailing = view.layoutMargins.trailing - view.safeAreaInsets.trailing

        guard contentInset != stickerCollectionView.contentInset else { return }

        stickerCollectionView.contentInset = contentInset
        stickerCollectionView.contentOffset.y = -stickerCollectionView.adjustedContentInset.top
    }

    /// Helper to ensure the navigation title only appears when the user starts scrolling
    private func updateNavigationTitleVisibility() {
        let restOffset = -stickerCollectionView.adjustedContentInset.top
        let scrolled = stickerCollectionView.contentOffset.y - restOffset
        let shouldShow = scrolled > 60
        let targetAlpha: CGFloat = shouldShow ? 1 : 0
        guard navigationItem.titleView?.alpha != targetAlpha else { return }
        UIView.animate(withDuration: 0.2) {
            self.navigationItem.titleView?.alpha = targetAlpha
        }
    }

    private lazy var installButton: UIButton = {
        UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "STICKERS_INSTALL_BUTTON",
                comment: "Label for the 'install sticker pack' button.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapInstall()
            },
        )
    }()

    private lazy var bottomButtonContainer: UIView = {
        UIStackView.verticalButtonStack(buttons: [installButton], isFullWidthButtons: true)
    }()

    private var loadingIndicator = UIActivityIndicatorView(style: .large)

    private var loadFailedLabel: UILabel = {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "STICKERS_PACK_VIEW_FAILED_TO_LOAD",
            comment: "Label indicating that the sticker pack failed to load.",
        )
        label.font = UIFont.dynamicTypeBody
        label.textColor = .Signal.label
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentHuggingHigh()
        label.setCompressionResistanceHigh()
        return label
    }()

    // We use this timer to ensure that we don't show the
    // loading indicator for N seconds, to prevent a "flash"
    // when presenting the view.
    private var loadTimer: Timer?
    private var loadTimerHasFired = false

    private func updateContent() {
        guard !isDismissing else { return }

        guard let stickerPack = dataSource.getStickerPack() else {
            stickerCollectionView.reconfigureCustomHeader()
            bottomButtonContainer.isHidden = true

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

        bottomButtonContainer.isHidden = false

        loadFailedLabel.isHidden = true
        loadingIndicator.isHidden = true
        loadingIndicator.stopAnimating()

        // Nav bar title / default-pack icon
        let defaultTitle = OWSLocalizedString(
            "STICKERS_PACK_VIEW_DEFAULT_TITLE",
            comment: "The default title for the 'sticker pack' view.",
        )
        if let title = stickerPack.title?.ows_stripped(), !title.isEmpty {
            navBarTitleLabel.text = title.filterForDisplay
        } else {
            navBarTitleLabel.text = defaultTitle
        }
        let isDefaultStickerPack = StickerManager.isDefaultStickerPack(packId: stickerPack.info.packId)
        navBarDefaultPackImage.isHidden = !isDefaultStickerPack

        // We need to consult StickerManager for the latest "isInstalled"
        // state, since the data source may be caching stale state.
        let isInstalled = StickerManager.isStickerPackInstalled(stickerPackInfo: stickerPack.info)
        installButton.isHidden = isInstalled

        // Pack info header (title, author, count/size, cover, buttons)
        stickerCollectionView.reconfigureCustomHeader()
    }

    // MARK: Events

    private var isDismissing = false

    private func didTapInstall() {
        isDismissing = true

        guard let stickerPack = dataSource.getStickerPack() else {
            owsFailDebug("Missing sticker pack.")
            return
        }

        var config = installButton.configuration
        config?.showsActivityIndicator = true
        config?.title = nil
        installButton.configuration = config

        Task { [weak self] in
            guard let self else { return }
            await db.awaitableWrite { transaction in
                StickerManager.installStickerPack(
                    stickerPack: stickerPack,
                    wasLocallyInitiated: true,
                    transaction: transaction,
                )
            }
            DispatchQueue.main.async {
                var config = self.installButton.configuration
                config?.showsActivityIndicator = false
                config?.title = OWSLocalizedString(
                    "STICKERS_INSTALL_BUTTON",
                    comment: "Label for the 'install sticker pack' button.",
                )
                self.installButton.configuration = config

                self.dismiss(animated: true)
            }
        }
    }

    private func didTapUninstall() {
        let confirmUninstallSheet = ActionSheetController(
            title: OWSLocalizedString("STICKER_PACK_CONFIRM_REMOVE_TITLE", comment: "Title for a sheet asking the user to confirm they want to remove a sticker pack"),
            message: OWSLocalizedString("STICKER_PACK_CONFIRM_REMOVE_MESSAGE", comment: "Message for a sheet asking the user to confirm they want to remove a sticker pack"),
        )

        confirmUninstallSheet.addAction(
            ActionSheetAction(
                title: OWSLocalizedString(
                    "STICKER_PACK_CONFIRM_REMOVE_BUTTON",
                    comment: "Button to confirm a user wants to remove a sticker pack",
                ),
                style: .destructive,
                handler: { [weak self] _ in
                    self?.didConfirmUninstall()
                },
            ),
        )
        confirmUninstallSheet.addAction(.cancel)
        presentActionSheet(confirmUninstallSheet)
    }

    private func didConfirmUninstall() {
        isDismissing = true

        let stickerPackInfo = self.stickerPackInfo
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false,
            presentationDelay: 0,
            backgroundBlock: { [db] modal in
                db.write { transaction in
                    StickerManager.uninstallStickerPack(
                        stickerPackInfo: stickerPackInfo,
                        wasLocallyInitiated: true,
                        transaction: transaction,
                    )
                }
                DispatchQueue.main.async {
                    modal.dismiss {
                        self.dismiss(animated: true)
                    }
                }
            },
        )
    }

    private func dismissButtonPressed() {
        AssertIsOnMainThread()

        isDismissing = true

        dismiss(animated: true)
    }

    // We need to retain a link to the send flow during the send flow.
    private var sendMessageFlow: SendMessageFlow?

    private func linkButtonPressed() {
        guard let stickerPack = dataSource.getStickerPack() else {
            owsFailDebug("Missing sticker pack.")
            return
        }

        let sheet = StickerPackShareSheetViewController(
            stickerPack: stickerPack,
            stickerPackDataSource: dataSource,
            onSendInSignal: { [weak self] in self?.shareButtonPressed() },
            onCopyLink: { [weak self] in self?.copyLinkToPasteboard() },
            onShare: { [weak self] in
                guard let self else { return }
                ShareActivityUtil.present(
                    activityItems: [stickerPack.info.shareUrl()],
                    from: self,
                    sourceView: self.view,
                )
            },
        )
        present(sheet, animated: true)
    }

    private func copyLinkToPasteboard() {
        UIPasteboard.general.string = stickerPackInfo.shareUrl()
        presentToast(
            text: OWSLocalizedString(
                "COPIED_TO_CLIPBOARD",
                comment: "Indicator that a value has been copied to the clipboard.",
            ),
        )
    }

    private func shareButtonPressed() {
        guard let stickerPack = dataSource.getStickerPack() else {
            owsFailDebug("Missing sticker pack.")
            return
        }

        let packUrl = stickerPack.info.shareUrl()
        let messageBody = MessageBody(text: packUrl, ranges: .empty)
        guard let unapprovedContent = SendMessageUnapprovedContent(messageBody: messageBody) else {
            owsFailDebug("Missing messageBody.")
            return
        }
        let navigationController = OWSNavigationController()
        let sendMessageFlow = SendMessageFlow(
            unapprovedContent: unapprovedContent,
            presentationStyle: .pushOnto(navigationController),
            delegate: self,
        )
        // Retain the flow until it is complete.
        self.sendMessageFlow = sendMessageFlow

        present(navigationController, animated: true)
    }

    @objc
    private func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        updateContent()
    }

    // MARK: - StickerPackDataSourceDelegate

    func stickerPackDataDidChange() {
        AssertIsOnMainThread()

        updateContent()
    }

    // MARK: - StickerPackCollectionViewDelegate

    func didSelectSticker(_ stickerMetadata: any StickerMetadata) {
        let stickerDetailsSheet = StickerDetailSheet(
            db: db,
            stickerMetadata: stickerMetadata,
            actions: [
                StickerDetailSheet.Action(
                    icon: .buttonForward,
                    title: OWSLocalizedString(
                        "SEND_BUTTON_TITLE",
                        comment: "Label for the button to send a message",
                    ),
                    handler: { [weak self] in
                        guard let self else { return }
                        self.sendStickerFlow = SendStickerFlow(stickerMetadata: stickerMetadata, db: db)
                        self.sendStickerFlow?.present(from: self)
                    },
                ),
            ],
        )
        present(stickerDetailsSheet, animated: true)
    }

    func stickerPreviewHostView() -> UIView? {
        return view
    }

    func stickerPreviewHasOverlay() -> Bool {
        return true
    }

    func didRequestQuoteReplyPreview(for stickerMetadata: any StickerMetadata, stickerView: UIView) {
        owsFailDebug("")
    }

    func shouldShowStickerPreview() -> Bool {
        return false
    }

    // MARK: - SendMessageDelegate

    func sendMessageFlowDidComplete(threads: [TSThread]) {
        AssertIsOnMainThread()

        sendMessageFlow = nil

        dismiss(animated: true)
    }

    func sendMessageFlowWillShowConversation() {
        AssertIsOnMainThread()

        sendMessageFlow = nil

        // Don't dismiss anything -- the flow does that itself.
    }

    func sendMessageFlowDidCancel() {
        AssertIsOnMainThread()

        sendMessageFlow = nil

        dismiss(animated: true)
    }
}

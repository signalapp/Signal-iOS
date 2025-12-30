//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class StickerPackViewController: OWSViewController {

    // MARK: Properties

    private let stickerPackInfo: StickerPackInfo

    private let dataSource: StickerPackDataSource

    // MARK: UIViewController

    init(stickerPackInfo: StickerPackInfo) {
        self.stickerPackInfo = stickerPackInfo
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

    override func viewDidLoad() {
        super.viewDidLoad()

        view.overrideUserInterfaceStyle = .dark
        view.backgroundColor = .Signal.background

        // Toolbar at the top.
        let toolbar: UIToolbar = if #available(iOS 26, *) { UIToolbar() } else { UIToolbar.clear() }
        toolbar.items = [
            UIBarButtonItem(
                image: Theme.iconImage(.buttonX),
                primaryAction: UIAction { [weak self] _ in
                    self?.dismissButtonPressed()
                },
            ),
            UIBarButtonItem.flexibleSpace(),
            shareBarButtonItem,
        ]
        if #unavailable(iOS 26) {
            toolbar.tintColor = Theme.darkThemeLegacyPrimaryIconColor
        }

        // Header: Cover, Text.
        let textRowsView = UIStackView(arrangedSubviews: [titleLabel])
        textRowsView.axis = .vertical
        textRowsView.alignment = .leading

        // Default Pack icon, Author
        let bottomRow = UIStackView(arrangedSubviews: [defaultPackIconView, authorLabel])
        bottomRow.axis = .horizontal
        bottomRow.alignment = .center
        bottomRow.spacing = 6
        textRowsView.addArrangedSubview(bottomRow)

        let packInfoView = UIStackView(arrangedSubviews: [coverView, textRowsView])
        packInfoView.axis = .horizontal
        packInfoView.alignment = .center
        packInfoView.spacing = 12
        packInfoView.isLayoutMarginsRelativeArrangement = true
        packInfoView.preservesSuperviewLayoutMargins = true
        self.stickerPackInfoView = packInfoView

        let headerView = UIStackView(arrangedSubviews: [toolbar, packInfoView])
        headerView.axis = .vertical
        headerView.spacing = 16
        headerView.preservesSuperviewLayoutMargins = true
        view.addSubview(headerView)
        self.headerView = headerView

        // Sticker Collection View
        view.insertSubview(stickerCollectionView, belowSubview: headerView)

        // Install / Uninstall at the bottom
        view.addSubview(bottomButtonContainer)

        coverView.translatesAutoresizingMaskIntoConstraints = false
        headerView.translatesAutoresizingMaskIntoConstraints = false
        stickerCollectionView.translatesAutoresizingMaskIntoConstraints = false
        bottomButtonContainer.translatesAutoresizingMaskIntoConstraints = false

        // This will be adjusted in `viewLayoutMarginsDidChange` so that top and leading margins are equal
        // and close button is in perfect corner position.
        headerViewTopEdgeConstraint = headerView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor)

        NSLayoutConstraint.activate([
            coverView.widthAnchor.constraint(equalToConstant: 64),
            coverView.heightAnchor.constraint(equalToConstant: 64),

            headerViewTopEdgeConstraint!,
            headerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            stickerCollectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stickerCollectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            bottomButtonContainer.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            bottomButtonContainer.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            bottomButtonContainer.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
        ])

        // iOS 26: collection view goes from top to bottom,
        // content underneath header and footer is obscured via UIScrollEdgeElementContainerInteraction.
        // Collection view insets (top and bottom) are adjusted in `viewDidLayoutSubviews`.
        if #available(iOS 26, *) {
            NSLayoutConstraint.activate([
                stickerCollectionView.topAnchor.constraint(equalTo: view.topAnchor),
                stickerCollectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])

            // Scroll Edge Interactions
            let topEdgeInteraction = UIScrollEdgeElementContainerInteraction()
            topEdgeInteraction.edge = .top
            topEdgeInteraction.scrollView = stickerCollectionView
            packInfoView.addInteraction(topEdgeInteraction)

            let bottomEdgeInteraction = UIScrollEdgeElementContainerInteraction()
            bottomEdgeInteraction.edge = .bottom
            bottomEdgeInteraction.scrollView = stickerCollectionView
            bottomButtonContainer.addInteraction(bottomEdgeInteraction)
        }
        // iOS 15-18: collection view is simply placed between header and footer.
        else {
            NSLayoutConstraint.activate([
                stickerCollectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16),
                stickerCollectionView.bottomAnchor.constraint(equalTo: bottomButtonContainer.topAnchor, constant: -16),
            ])
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

        StickerManager.refreshContents()
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

        if let headerViewTopEdgeConstraint {
            let leadingInset = view.layoutMargins.leading - view.safeAreaInsets.leading
            headerViewTopEdgeConstraint.constant = leadingInset
        }

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

        fromViewController.presentFormSheet(self, animated: animated) {
            // ensure any presented keyboard is dismissed, this seems to be
            // an issue only when opening signal from a universal link in
            // an external app
            self.becomeFirstResponder()
        }
    }

    // MARK: Layout

    private lazy var shareBarButtonItem: UIBarButtonItem = {
        UIBarButtonItem(
            image: UIImage(named: "forward"),
            primaryAction: UIAction { [weak self] _ in
                self?.shareButtonPressed()
            },
        )
    }()

    private let coverView = StickerReusableView()

    private var headerView: UIView!
    private var stickerPackInfoView: UIView!

    // This is adjusted to match leading view inset.
    private var headerViewTopEdgeConstraint: NSLayoutConstraint?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.label
        label.font = .dynamicTypeTitle1.semibold()
        label.numberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        return label
    }()

    private let authorLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.secondaryLabel
        label.font = .dynamicTypeBody
        return label
    }()

    private let defaultPackIconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "check-circle-fill-compact"))
        imageView.tintColor = .Signal.accent
        imageView.setContentHuggingHigh()
        imageView.setCompressionResistanceHigh()
        return imageView
    }()

    private let stickerCollectionView = StickerPackCollectionView(placeholderColor: .ows_blackAlpha60)

    private func updateCollectionViewContentInset() {
        var contentInset = stickerCollectionView.contentInset

        if #available(iOS 26, *) {
            // On iOS 26 collection view extends underneath header and footer.
            contentInset.top = headerView.frame.maxY + 16
            contentInset.bottom = bottomButtonContainer.frame.height + 16

            stickerCollectionView.verticalScrollIndicatorInsets.top = contentInset.top
            stickerCollectionView.verticalScrollIndicatorInsets.bottom = contentInset.bottom
        }
        contentInset.leading = view.layoutMargins.leading - view.safeAreaInsets.leading
        contentInset.trailing = view.layoutMargins.trailing - view.safeAreaInsets.trailing

        guard contentInset != stickerCollectionView.contentInset else { return }

        stickerCollectionView.contentInset = contentInset
        stickerCollectionView.contentOffset.y = -contentInset.top
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

    private lazy var uninstallButton: UIButton = {
        let button = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "STICKERS_UNINSTALL_BUTTON",
                comment: "Label for the 'uninstall sticker pack' button.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapUninstall()
            },
        )
        button.configuration?.baseBackgroundColor = .Signal.red
        return button
    }()

    private lazy var bottomButtonContainer: UIView = {
        UIStackView.verticalButtonStack(buttons: [installButton, uninstallButton], isFullWidthButtons: true)
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

        updateCover()

        guard let stickerPack = dataSource.getStickerPack() else {
            stickerPackInfoView.isHidden = true
            bottomButtonContainer.isHidden = true

            if #available(iOS 16, *) {
                shareBarButtonItem.isHidden = true
            } else {
                shareBarButtonItem.isEnabled = false
            }

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

        // Update visibility of UI elements.
        stickerPackInfoView.isHidden = false
        bottomButtonContainer.isHidden = false
        if #available(iOS 16, *) {
            shareBarButtonItem.isHidden = false
        } else {
            shareBarButtonItem.isEnabled = true
        }

        loadFailedLabel.isHidden = true
        loadingIndicator.isHidden = true
        loadingIndicator.stopAnimating()

        // Title and author
        let defaultTitle = OWSLocalizedString(
            "STICKERS_PACK_VIEW_DEFAULT_TITLE",
            comment: "The default title for the 'sticker pack' view.",
        )
        if let title = stickerPack.title?.ows_stripped(), !title.isEmpty {
            titleLabel.text = title.filterForDisplay
        } else {
            titleLabel.text = defaultTitle
        }

        let isDefaultStickerPack = StickerManager.isDefaultStickerPack(packId: stickerPack.info.packId)
        authorLabel.text = stickerPack.author?.filterForDisplay
        authorLabel.textColor = isDefaultStickerPack ? .Signal.accent : .Signal.label
        defaultPackIconView.isHidden = !isDefaultStickerPack

        // We need to consult StickerManager for the latest "isInstalled"
        // state, since the data source may be caching stale state.
        let isInstalled = StickerManager.isStickerPackInstalled(stickerPackInfo: stickerPack.info)
        installButton.isHidden = isInstalled
        uninstallButton.isHidden = !isInstalled
    }

    private func updateCover() {
        guard !coverView.hasStickerView else { return }

        guard let stickerPack = dataSource.getStickerPack() else { return }
        let coverInfo = stickerPack.coverInfo
        guard
            let stickerView = StickerView.stickerView(
                forStickerInfo: coverInfo,
                dataSource: dataSource,
            )
        else {
            coverView.showPlaceholder(color: .ows_blackAlpha60)
            return
        }

        coverView.configure(with: stickerView)
    }

    // MARK: Events

    private var isDismissing = false

    private func didTapInstall() {
        isDismissing = true

        guard let stickerPack = dataSource.getStickerPack() else {
            owsFailDebug("Missing sticker pack.")
            return
        }

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false,
            presentationDelay: 0,
            backgroundBlock: { modal in
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    StickerManager.installStickerPack(
                        stickerPack: stickerPack,
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

    private func didTapUninstall() {
        isDismissing = true

        let stickerPackInfo = self.stickerPackInfo
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false,
            presentationDelay: 0,
            backgroundBlock: { modal in
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
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
}

// MARK: -

private class StickerPackViewControllerAnimationController: UIPresentationController {

    let backdropView: UIView = UIView()

    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
        backdropView.backgroundColor = .Signal.backdrop
    }

    override func presentationTransitionWillBegin() {
        guard let containerView else { return }
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

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return StickerPackViewControllerAnimationController(presentedViewController: presented, presenting: presenting)
    }
}

// MARK: -

extension StickerPackViewController: StickerPackDataSourceDelegate {

    func stickerPackDataDidChange() {
        AssertIsOnMainThread()

        updateContent()
    }
}

// MARK: -

extension StickerPackViewController: StickerPackCollectionViewDelegate {

    func didSelectSticker(_: StickerInfo) {
        // This view controller does nothing.
    }

    func stickerPreviewHostView() -> UIView? {
        return view
    }

    func stickerPreviewHasOverlay() -> Bool {
        return true
    }
}

// MARK: -

extension StickerPackViewController: SendMessageDelegate {

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

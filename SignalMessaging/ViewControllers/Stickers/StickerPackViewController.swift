//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import YYImage

@objc
public class StickerPackViewController: OWSViewController {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: Properties

    private let stickerPackInfo: StickerPackInfo

    private let stickerCollectionView = StickerPackCollectionView()

    private let dataSource: StickerPackDataSource

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    public required init(stickerPackInfo: StickerPackInfo) {
        self.stickerPackInfo = stickerPackInfo
        self.dataSource = TransientStickerPackDataSource(stickerPackInfo: stickerPackInfo,
                                                         shouldDownloadAllStickers: true)

        super.init(nibName: nil, bundle: nil)

        self.modalPresentationStyle = .overFullScreen

        stickerCollectionView.stickerDelegate = self
        stickerCollectionView.show(dataSource: dataSource)
        dataSource.add(delegate: self)

        NotificationCenter.default.addObserver(self, selector: #selector(callDidChange), name: .OWSWindowManagerCallDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didChangeStatusBarFrame), name: UIApplication.didChangeStatusBarFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.stickersOrPacksDidChange,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - View Lifecycle

    override public func loadView() {
        super.loadView()

        if UIAccessibility.isReduceTransparencyEnabled {
            view.backgroundColor = Theme.darkThemeBackgroundColor
        } else {
            view.backgroundColor = UIColor(white: 0, alpha: 0.6)
            view.isOpaque = false

            let blurEffect = Theme.barBlurEffect
            let blurEffectView = UIVisualEffectView(effect: blurEffect)
            view.addSubview(blurEffectView)
            blurEffectView.autoPinEdgesToSuperviewEdges()
        }

        let hMargin: CGFloat = 16

        dismissButton.setTemplateImageName("x-24", tintColor: Theme.darkThemePrimaryColor)
        dismissButton.addTarget(self, action: #selector(dismissButtonPressed(sender:)), for: .touchUpInside)
        dismissButton.contentEdgeInsets = UIEdgeInsets(top: 20, leading: hMargin, bottom: 20, trailing: hMargin)
        dismissButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "dismissButton")

        coverView.autoSetDimensions(to: CGSize(width: 48, height: 48))
        coverView.setCompressionResistanceHigh()
        coverView.setContentHuggingHigh()

        titleLabel.textColor = Theme.darkThemePrimaryColor
        titleLabel.font = UIFont.ows_dynamicTypeTitle1.ows_mediumWeight()

        authorLabel.textColor = Theme.darkThemePrimaryColor
        authorLabel.font = UIFont.ows_dynamicTypeBody

        defaultPackIconView.setTemplateImageName("check-circle-filled-16", tintColor: UIColor.ows_signalBrandBlue)
        defaultPackIconView.isHidden = true

        if FeatureFlags.stickerSharing {
            shareButton.setTemplateImageName("forward-outline-24", tintColor: Theme.darkThemePrimaryColor)
            shareButton.addTarget(self, action: #selector(shareButtonPressed(sender:)), for: .touchUpInside)
            shareButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "shareButton")
        }

        view.addSubview(dismissButton)
        dismissButton.autoPinEdge(toSuperviewEdge: .leading)
        dismissButton.autoPin(toTopLayoutGuideOf: self, withInset: 0)

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

        self.view.addSubview(headerStack)
        headerStack.autoPinEdge(.top, to: .bottom, of: dismissButton)
        headerStack.autoPinWidthToSuperview()

        stickerCollectionView.backgroundColor = .clear
        self.view.addSubview(stickerCollectionView)
        stickerCollectionView.autoPinWidthToSuperview()
        stickerCollectionView.autoPinEdge(.top, to: .bottom, of: headerStack)

        let installButton = OWSFlatButton.button(title: NSLocalizedString("STICKERS_INSTALL_BUTTON", comment: "Label for the 'install sticker pack' button."),
                                             font: UIFont.ows_dynamicTypeBody.ows_mediumWeight(),
                                             titleColor: UIColor.ows_materialBlue,
                                             backgroundColor: UIColor.white,
                                             target: self,
                                             selector: #selector(didTapInstall))
        self.installButton = installButton
        installButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "installButton")
        let uninstallButton = OWSFlatButton.button(title: NSLocalizedString("STICKERS_UNINSTALL_BUTTON", comment: "Label for the 'uninstall sticker pack' button."),
                                             font: UIFont.ows_dynamicTypeBody.ows_mediumWeight(),
                                             titleColor: UIColor.ows_materialBlue,
                                             backgroundColor: UIColor.white,
                                             target: self,
                                             selector: #selector(didTapUninstall))
        self.uninstallButton = uninstallButton
        uninstallButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "uninstallButton")
        for button in [installButton, uninstallButton] {
            view.addSubview(button)
            button.autoPin(toBottomLayoutGuideOf: self, withInset: 10)
            button.autoPinEdge(.top, to: .bottom, of: stickerCollectionView)
            button.autoPinWidthToSuperview(withMargin: hMargin)
            button.autoSetHeightUsingFont()
        }

        view.addSubview(loadingIndicator)
        loadingIndicator.autoCenterInSuperview()

        loadFailedLabel.text = NSLocalizedString("STICKERS_PACK_VIEW_FAILED_TO_LOAD",
                                                 comment: "Label indicating that the sticker pack failed to load.")
        loadFailedLabel.font = UIFont.ows_dynamicTypeBody
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
    private let coverView = YYAnimatedImageView()
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
        if let title = stickerPack.title?.ows_stripped(),
            title.count > 0 {
            titleLabel.text = title.filterForDisplay
        } else {
            titleLabel.text = defaultTitle
        }

        authorLabel.text = stickerPack.author?.filterForDisplay

        defaultPackIconView.isHidden = !StickerManager.isDefaultStickerPack(stickerPack.info)

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
        guard let stickerPack = dataSource.getStickerPack() else {
            coverView.isHidden = true
            return
        }
        let coverInfo = stickerPack.coverInfo
        guard let filePath = dataSource.filePath(forSticker: coverInfo) else {
            // This can happen if the pack hasn't been saved yet, e.g.
            // this view was opened from a sticker pack URL or share.
            Logger.warn("Missing sticker data file path.")
            coverView.isHidden = true
            return
        }
        guard NSData.ows_isValidImage(atPath: filePath, mimeType: OWSMimeTypeImageWebp) else {
            owsFailDebug("Invalid sticker.")
            coverView.isHidden = true
            return
        }
        guard let stickerImage = YYImage(contentsOfFile: filePath) else {
            owsFailDebug("Sticker could not be parsed.")
            coverView.isHidden = true
            return
        }

        coverView.image = stickerImage
        coverView.isHidden = false
    }

    private func updateInsets() {
        UIView.setAnimationsEnabled(false)

        if #available(iOS 11.0, *) {
            if (!CurrentAppContext().isMainApp) {
                self.additionalSafeAreaInsets = .zero
            } else if (OWSWindowManager.shared().hasCall()) {
                self.additionalSafeAreaInsets = UIEdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0)
            } else {
                self.additionalSafeAreaInsets = .zero
            }
        }
        UIView.setAnimationsEnabled(true)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        StickerManager.refreshContents()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.becomeFirstResponder()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.becomeFirstResponder()
    }

    override public var canBecomeFirstResponder: Bool {
        return true
    }

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    // - MARK: Events

    @objc
    private func didTapInstall(sender: UIButton) {
        AssertIsOnMainThread()

        Logger.verbose("")

        guard let stickerPack = dataSource.getStickerPack() else {
            owsFailDebug("Missing sticker pack.")
            return
        }

        databaseStorage.write { (transaction) in
            StickerManager.installStickerPack(stickerPack: stickerPack,
                                              transaction: transaction)
        }

        updateContent()

        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false) { modal in
                                                        // Downloads for this sticker pack will already be enqueued by
                                                        // StickerManager.saveStickerPack above.  We just use this
                                                        // method to determine whether all sticker downloads succeeded.
                                                        // Re-enqueuing should be cheap since already-downloaded stickers
                                                        // will succeed immediately and failed stickers will fail again
                                                        // quickly... or succeed this time.
                                                        StickerManager.ensureDownloadsAsync(forStickerPack: stickerPack)
                                                            .done {
                                                                modal.dismiss {
                                                                    // Do nothing.
                                                                }
                                                            }.catch { (_) in
                                                                modal.dismiss {
                                                                    OWSAlerts.showErrorAlert(message: NSLocalizedString("STICKERS_PACK_INSTALL_FAILED", comment: "Error message shown when a sticker pack failed to install."))
                                                                }
                                                            }.retainUntilComplete()
        }
    }

    @objc
    private func didTapUninstall(sender: UIButton) {
        AssertIsOnMainThread()

        Logger.verbose("")

        databaseStorage.write { (transaction) in
            StickerManager.uninstallStickerPack(stickerPackInfo: self.stickerPackInfo,
                                                transaction: transaction)
        }

        updateContent()
    }

    @objc
    private func dismissButtonPressed(sender: UIButton) {
        AssertIsOnMainThread()

        dismiss(animated: true)
    }

    @objc
    func shareButtonPressed(sender: UIButton) {
        AssertIsOnMainThread()

        guard let stickerPack = dataSource.getStickerPack() else {
            owsFailDebug("Missing sticker pack.")
            return
        }

        StickerSharingViewController.shareStickerPack(stickerPack.info, from: self)
    }

    @objc
    public func callDidChange() {
        Logger.debug("")

        updateContent()
    }

    @objc
    public func didChangeStatusBarFrame() {
        Logger.debug("")

        updateContent()
    }

    @objc func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        Logger.verbose("")

        updateContent()
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

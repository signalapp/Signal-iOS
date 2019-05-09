//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class StickerPackViewController: OWSViewController {

    // MARK: - Dependencies

    private static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: Properties

    private let stickerPackInfo: StickerPackInfo

    private let stickerCollectionView = StickerPackCollectionView()

    private let dataSource: StickerPackDataSource

    private let hasDismissButton: Bool

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    public required init(stickerPackInfo: StickerPackInfo, hasDismissButton: Bool) {
        self.stickerPackInfo = stickerPackInfo
        self.hasDismissButton = hasDismissButton
        self.dataSource = TransientStickerPackDataSource(stickerPackInfo: stickerPackInfo)

        super.init(nibName: nil, bundle: nil)

        stickerCollectionView.show(dataSource: dataSource)
        dataSource.add(delegate: self)
    }

    // MARK: - View Lifecycle

    override public func loadView() {
        super.loadView()

        if UIAccessibility.isReduceTransparencyEnabled {
            view.backgroundColor = Theme.darkThemeBackgroundColor
        } else {
            view.backgroundColor = .clear

            let blurEffect = Theme.darkThemeBarBlurEffect
            let blurEffectView = UIVisualEffectView(effect: blurEffect)
            view.addSubview(blurEffectView)
            blurEffectView.autoPinEdgesToSuperviewEdges()
        }

        titleLabel.textColor = Theme.darkThemePrimaryColor
        titleLabel.font = UIFont.ows_dynamicTypeTitle1.ows_mediumWeight()

        authorLabel.textColor = Theme.darkThemePrimaryColor
        authorLabel.font = UIFont.ows_dynamicTypeBody

        defaultPackIconView.setTemplateImageName("badge-filled-16", tintColor: UIColor.ows_signalBrandBlue)
        defaultPackIconView.isHidden = true

        shareButton.setTemplateImageName("badge-filled-16", tintColor: Theme.darkThemePrimaryColor)
        shareButton.addTarget(self, action: #selector(shareButtonPressed(sender:)), for: .touchUpInside)

        let bottomRowView = UIStackView(arrangedSubviews: [ defaultPackIconView, authorLabel ])
        bottomRowView.axis = .horizontal
        bottomRowView.alignment = .center
        bottomRowView.spacing = 5
        defaultPackIconView.setCompressionResistanceHigh()
        defaultPackIconView.setContentHuggingHigh()

        let textRowsView = UIStackView(arrangedSubviews: [ titleLabel, bottomRowView ])
        textRowsView.axis = .vertical
        textRowsView.alignment = .leading

        let headerStack = UIStackView(arrangedSubviews: [ textRowsView, shareButton ])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 10
        headerStack.layoutMargins = UIEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
        headerStack.isLayoutMarginsRelativeArrangement = true
        textRowsView.setCompressionResistanceHorizontalLow()
        textRowsView.setContentHuggingHorizontalLow()

        self.view.addSubview(headerStack)
        headerStack.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        headerStack.autoPinWidthToSuperview()

        stickerCollectionView.backgroundColor = .clear
        self.view.addSubview(stickerCollectionView)
        stickerCollectionView.autoPinWidthToSuperview()
        stickerCollectionView.autoPinEdge(.top, to: .bottom, of: headerStack)
        stickerCollectionView.autoPinEdge(toSuperviewMargin: .bottom)

        // TODO: We probably want to surface the author and perhaps the cover.
        //       design is pending.

        updateHeader()
        updateNavigationBar()
    }

    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    private let defaultPackIconView = UIImageView()
    private let shareButton = UIButton()

    private func updateHeader() {
        guard let stickerPack = dataSource.getStickerPack() else {
            return
        }

        titleLabel.text = stickerPack.title
        authorLabel.text = stickerPack.author

        defaultPackIconView.isHidden = !StickerManager.isDefaultStickerPack(stickerPack)
        shareButton.isHidden = !FeatureFlags.stickerPackSharing
    }

    private func updateNavigationBar() {
        AssertIsOnMainThread()

        let defaultTitle = NSLocalizedString("STICKERS_PACK_VIEW_DEFAULT_TITLE", comment: "The default title for the 'sticker pack' view.")

        if let stickerPack = dataSource.getStickerPack() {
            if let title = stickerPack.title?.ows_stripped(),
                title.count > 0 {
                navigationItem.title = title
            } else {
                navigationItem.title = defaultTitle
            }

            // We need to consult StickerManager for the latest "isInstalled"
            // state, since the data source may be caching stale state.
            let isInstalled = StickerManager.isStickerPackInstalled(stickerPackInfo: stickerPack.info)
            if isInstalled {
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("STICKERS_UNINSTALL_BUTTON", comment: "Label for the 'uninstall sticker pack' button."),
                                                                         style: .plain,
                                                                         target: self,
                                                                         action: #selector(didTapUninstall))
            } else {
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("STICKERS_INSTALL_BUTTON", comment: "Label for the 'install sticker pack' button."),
                                                                         style: .plain,
                                                                         target: self,
                                                                         action: #selector(didTapInstall))
            }
        } else {
            navigationItem.title = defaultTitle
            navigationItem.rightBarButtonItem = nil
        }

        if hasDismissButton {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(didPressDismiss))
        }
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

    // MARK: Events

    @objc
    private func didTapInstall(sender: UIButton) {
        AssertIsOnMainThread()

        Logger.verbose("")

        guard let stickerPack = dataSource.getStickerPack() else {
            owsFailDebug("Missing sticker pack.")
            return
        }

        StickerManager.saveStickerPack(stickerPack: stickerPack, installMode: .install)

        updateNavigationBar()
    }

    @objc
    private func didTapUninstall(sender: UIButton) {
        AssertIsOnMainThread()

        Logger.verbose("")

        StickerPackViewController.databaseStorage.write { (transaction) in
            StickerManager.uninstallStickerPack(stickerPackInfo: self.stickerPackInfo,
                                                transaction: transaction)
        }

        updateNavigationBar()
    }

    @objc
    private func didPressDismiss(sender: UIButton) {
        AssertIsOnMainThread()

        Logger.verbose("")

        dismiss(animated: true)
    }

    @objc
    func shareButtonPressed(sender: UIButton) {
    }
}

// MARK: -

extension StickerPackViewController: StickerPackDataSourceDelegate {
    public func stickerPackDataDidChange() {
        AssertIsOnMainThread()

        updateHeader()
        updateNavigationBar()
    }
}

//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

private class StickerPackActionButton: UIView {

    private let block: () -> Void

    @available(*, unavailable, message: "use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(actionIconName: String, block: @escaping () -> Void) {
        self.block = block

        super.init(frame: .zero)

        configure(actionIconName: actionIconName)
    }

    private func configure(actionIconName: String) {
        let actionIconSize: CGFloat = 20
        let actionCircleSize: CGFloat = 32
        let actionCircleView = CircleView(diameter: actionCircleSize)
        actionCircleView.backgroundColor = Theme.washColor
        let actionIcon = UIImage(named: actionIconName)?.withRenderingMode(.alwaysTemplate)
        let actionIconView = UIImageView(image: actionIcon)
        actionIconView.tintColor = Theme.secondaryTextAndIconColor
        actionCircleView.addSubview(actionIconView)
        actionIconView.autoCenterInSuperview()
        actionIconView.autoSetDimensions(to: CGSize(square: actionIconSize))

        self.addSubview(actionCircleView)
        actionCircleView.autoPinEdgesToSuperviewEdges()

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                    action: #selector(didTapButton)))
    }

    @objc
    func didTapButton(sender: UIGestureRecognizer) {
        block()
    }
}

// MARK: -

public class ManageStickersViewController: OWSTableViewController2 {

    // MARK: Initializers

    public required override init() {
        super.init()
    }

    // MARK: - View Lifecycle

    override public func loadView() {
        super.loadView()

        navigationItem.title = OWSLocalizedString("STICKERS_MANAGE_VIEW_TITLE", comment: "Title for the 'manage stickers' view.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(didPressDismiss))
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(packsDidChange),
                                               name: StickerManager.packsDidChange,
                                               object: nil)

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + iconSize + iconSpacing

        updateState()

        StickerManager.refreshContents()
    }

    private var pendingModalVC: ModalActivityIndicatorViewController?

    private var needsStateUpdate = false {
        didSet {
            if needsStateUpdate {
                updateEvent.requestNotify()
            }
        }
    }

    private var needsTableUpdate = false {
        didSet {
            if needsTableUpdate {
                updateEvent.requestNotify()
            }
        }
    }

    private lazy var updateEvent: DebouncedEvent = {
        DebouncedEvents.build(mode: .firstLast,
                              maxFrequencySeconds: 0.75,
                              onQueue: .asyncOnQueue(queue: .main)) { [weak self] in
            guard let self = self else { return }
            if self.needsStateUpdate {
                self.updateState()
            } else if self.needsTableUpdate {
                self.buildTable()
            }
        }
    }()

    private var installedStickerPackSources = [StickerPackDataSource]()
    private var availableBuiltInStickerPackSources = [StickerPackDataSource]()
    private var knownStickerPackSources = [StickerPackDataSource]()

    private func updateState() {
        // If we're presenting a modal because the user tapped install, dismiss it.
        pendingModalVC?.dismiss()
        pendingModalVC = nil

        // We need to recycle data sources to maintain continuity.
        var oldInstalledSources = [StickerPackInfo: StickerPackDataSource]()
        var oldTransientSources = [StickerPackInfo: StickerPackDataSource]()
        let updateMapWithOldSources = { (map: inout [StickerPackInfo: StickerPackDataSource], sources: [StickerPackDataSource]) in
            for source in sources {
                guard let info = source.info else {
                    owsFailDebug("Source missing info.")
                    continue
                }
                map[info] = source
            }
        }
        updateMapWithOldSources(&oldInstalledSources, installedStickerPackSources)
        updateMapWithOldSources(&oldTransientSources, availableBuiltInStickerPackSources)
        updateMapWithOldSources(&oldTransientSources, knownStickerPackSources)

        var installedStickerPacks = [StickerPack]()
        var availableBuiltInStickerPacks = [StickerPack]()
        var availableKnownStickerPacks = [KnownStickerPack]()
        self.databaseStorage.read { (transaction) in
            let allPacks = StickerManager.allStickerPacks(transaction: transaction)
            let allPackInfos = allPacks.map { $0.info }

            // Only show packs with installed covers.
            let packsWithCovers = allPacks.filter {
                StickerManager.isStickerInstalled(stickerInfo: $0.coverInfo,
                                                  transaction: transaction)
            }
            // Sort sticker packs by "date saved, descending" so that we feature
            // packs that the user has just learned about.
            installedStickerPacks = packsWithCovers.filter { $0.isInstalled }
            availableBuiltInStickerPacks = packsWithCovers.filter {
                !$0.isInstalled && StickerManager.isDefaultStickerPack(packId: $0.info.packId)
            }
            let allKnownStickerPacks = StickerManager.allKnownStickerPacks(transaction: transaction)
            availableKnownStickerPacks = allKnownStickerPacks.filter { !allPackInfos.contains($0.info) }
        }

        let installedSource = { (info: StickerPackInfo) -> StickerPackDataSource in
            if let source = oldInstalledSources[info] {
                return source
            }
            let source = InstalledStickerPackDataSource(stickerPackInfo: info)
            source.add(delegate: self)
            return source
        }
        let transientSource = { (info: StickerPackInfo) -> StickerPackDataSource in
            if let source = oldTransientSources[info] {
                return source
            }
            // Don't download all stickers; we only need covers for this view.
            let source = TransientStickerPackDataSource(stickerPackInfo: info,
                                                        shouldDownloadAllStickers: false)
            source.add(delegate: self)
            return source
        }
        let sortAvailablePacks = { (pack0: StickerPack, pack1: StickerPack) -> Bool in
            return pack0.dateCreated > pack1.dateCreated
        }
        let sortKnownPacks = { (pack0: KnownStickerPack, pack1: KnownStickerPack) -> Bool in
            return pack0.dateCreated > pack1.dateCreated
        }

        self.installedStickerPackSources = installedStickerPacks.sorted {
            $0.dateCreated > $1.dateCreated
            }.map { installedSource($0.info) }
        self.availableBuiltInStickerPackSources = availableBuiltInStickerPacks.sorted(by: sortAvailablePacks)
            .map { transientSource($0.info) }
        self.knownStickerPackSources = availableKnownStickerPacks.sorted(by: sortKnownPacks)
            .map { transientSource($0.info) }

        needsStateUpdate = false
        buildTable()
    }

    private func buildTable() {
        let contents = OWSTableContents()

        let installedSection = OWSTableSection()
        installedSection.headerTitle = OWSLocalizedString("STICKERS_MANAGE_VIEW_INSTALLED_PACKS_SECTION_TITLE", comment: "Title for the 'installed stickers' section of the 'manage stickers' view.")
        if installedStickerPackSources.count < 1 {
            let text = OWSLocalizedString("STICKERS_MANAGE_VIEW_NO_INSTALLED_PACKS", comment: "Label indicating that the user has no installed sticker packs.")
            installedSection.add(buildEmptySectionItem(labelText: text))
        }
        for dataSource in installedStickerPackSources {
            installedSection.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    return UITableViewCell()
                }
                return self.buildTableCell(installedStickerPack: dataSource)
                },
                                     actionBlock: { [weak self] in
                                        guard let packInfo = dataSource.info else {
                                            owsFailDebug("Source missing info.")
                                            return
                                        }
                                        self?.show(packInfo: packInfo)
            }))
        }
        contents.addSection(installedSection)

        let itemForAvailablePack = { (dataSource: StickerPackDataSource) -> OWSTableItem in
            OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    return UITableViewCell()
                }
                return self.buildTableCell(availableStickerPack: dataSource)
                },
                         actionBlock: { [weak self] in
                            guard let packInfo = dataSource.info else {
                                owsFailDebug("Source missing info.")
                                return
                            }
                            self?.show(packInfo: packInfo)
            })
        }
        if availableBuiltInStickerPackSources.count > 0 {
            let section = OWSTableSection()
            section.headerTitle = OWSLocalizedString("STICKERS_MANAGE_VIEW_AVAILABLE_BUILT_IN_PACKS_SECTION_TITLE", comment: "Title for the 'available built-in stickers' section of the 'manage stickers' view.")
            for dataSource in availableBuiltInStickerPackSources {
                section.add(itemForAvailablePack(dataSource))
            }
            contents.addSection(section)
        }

        // Sticker packs whose manifest is available.
        var loadedKnownStickerPackSources = [StickerPackDataSource]()
        // Sticker packs whose manifest is downloading.
        var loadingKnownStickerPackSources = [StickerPackDataSource]()
        // Sticker packs whose manifest download failed permanently.
        var failedKnownStickerPackSources = [StickerPackDataSource]()
        for source in knownStickerPackSources {
            guard source.getStickerPack() == nil else {
                // Already loaded.
                loadedKnownStickerPackSources.append(source)
                continue
            }
            guard let info = source.info else {
                owsFailDebug("Known source missing info.")
                continue
            }
            // Hide sticker packs whose download failed permanently.
            let isFailed = StickerManager.isStickerPackMissing(stickerPackInfo: info)
            if isFailed {
                failedKnownStickerPackSources.append(source)
            } else {
                loadingKnownStickerPackSources.append(source)
            }
        }
        let knownSection = OWSTableSection()
        knownSection.headerTitle = OWSLocalizedString("STICKERS_MANAGE_VIEW_AVAILABLE_KNOWN_PACKS_SECTION_TITLE", comment: "Title for the 'available known stickers' section of the 'manage stickers' view.")
        if knownStickerPackSources.count < 1 {
            let text = OWSLocalizedString("STICKERS_MANAGE_VIEW_NO_KNOWN_PACKS", comment: "Label indicating that the user has no known sticker packs.")
            knownSection.add(buildEmptySectionItem(labelText: text))
        }
        for dataSource in loadedKnownStickerPackSources {
            knownSection.add(itemForAvailablePack(dataSource))
        }
        if loadingKnownStickerPackSources.count > 0 {
            let text = OWSLocalizedString("STICKERS_MANAGE_VIEW_LOADING_KNOWN_PACKS",
                                         comment: "Label indicating that one or more known sticker packs is loading.")
            knownSection.add(buildEmptySectionItem(labelText: text))
        } else if failedKnownStickerPackSources.count > 0 {
            let text = OWSLocalizedString("STICKERS_MANAGE_VIEW_FAILED_KNOWN_PACKS",
                                         comment: "Label indicating that one or more known sticker packs failed to load.")
            knownSection.add(buildEmptySectionItem(labelText: text))
        }
        contents.addSection(knownSection)

        self.contents = contents
        needsTableUpdate = false
    }

    private func buildTableCell(installedStickerPack dataSource: StickerPackDataSource) -> UITableViewCell {
        let actionIconName = CurrentAppContext().isRTL ? "reply-filled-24" : "reply-filled-reversed-24"

        return buildTableCell(dataSource: dataSource,
                              actionIconName: actionIconName) { [weak self] in
                                guard let packInfo = dataSource.info else {
                                    owsFailDebug("Source missing info.")
                                    return
                                }
                                self?.share(packInfo: packInfo)
        }
    }

    private func buildTableCell(availableStickerPack dataSource: StickerPackDataSource) -> UITableViewCell {
        if let stickerPack = dataSource.getStickerPack() {
            let actionIconName = Theme.iconName(.messageActionSave24)
            return buildTableCell(dataSource: dataSource,
                                  actionIconName: actionIconName) { [weak self] in
                                    self?.install(stickerPack: stickerPack)
            }
        } else {
            // Hide "install" button if manifest isn't downloaded yet.
            return buildTableCell(dataSource: dataSource,
                                  actionIconName: nil) { }
        }
    }

    private typealias StickerViewCache = LRUCache<Data, ThreadSafeCacheHandle<StickerReusableView>>
    private let reusableCoverViewCache = StickerViewCache(maxSize: 16, shouldEvacuateInBackground: true)
    private func reusableCoverView(forDataSource dataSource: StickerPackDataSource) -> StickerReusableView? {
        guard let packId = dataSource.info?.packId else { return nil }

        let view: StickerReusableView = {
            if let view = reusableCoverViewCache.object(forKey: packId)?.value {
                return view
            }
            let view = StickerReusableView()
            reusableCoverViewCache.setObject(ThreadSafeCacheHandle(view), forKey: packId)
            return view
        }()

        guard !view.hasStickerView else { return view }

        guard let stickerInfo = dataSource.installedCoverInfo,
              let imageView = imageView(forStickerInfo: stickerInfo, dataSource: dataSource) else {
            view.showPlaceholder()
            return view
        }

        view.configure(with: imageView)

        return view
    }

    private let iconSize: CGFloat = 56
    private let iconSpacing: CGFloat = 12
    private func buildTableCell(dataSource: StickerPackDataSource,
                                actionIconName: String?,
                                block: @escaping () -> Void) -> UITableViewCell {

        let cell = OWSTableItem.newCell()

        guard let packInfo = dataSource.info else {
            owsFailDebug("Source missing info.")
            return cell
        }

        let titleValue = dataSource.title?.filterForDisplay
        let authorNameValue = dataSource.author?.filterForDisplay

        let iconView = reusableCoverView(forDataSource: dataSource) ?? UIView()
        iconView.autoSetDimensions(to: CGSize(square: iconSize))

        let title: String
        if let titleValue = titleValue?.ows_stripped(), !titleValue.isEmpty {
            title = titleValue
        } else {
            title = OWSLocalizedString("STICKERS_PACK_DEFAULT_TITLE", comment: "Default title for sticker packs.")
        }
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.dynamicTypeBody.semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let textStack = UIStackView(arrangedSubviews: [
            titleLabel
            ])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.setContentHuggingHorizontalLow()
        textStack.setCompressionResistanceHorizontalLow()

        // TODO: Should we show a default author name?

        let isDefaultStickerPack = StickerManager.isDefaultStickerPack(packId: packInfo.packId)

        var authorViews = [UIView]()
        if isDefaultStickerPack {
            let builtInPackView = UIImageView()
            builtInPackView.setTemplateImageName("check-circle-filled-16", tintColor: Theme.accentBlueColor)
            builtInPackView.setCompressionResistanceHigh()
            builtInPackView.setContentHuggingHigh()
            authorViews.append(builtInPackView)
        }

        if let authorName = authorNameValue?.ows_stripped(), !authorName.isEmpty {
            let authorLabel = UILabel()
            authorLabel.text = authorName
            authorLabel.font = isDefaultStickerPack ? UIFont.dynamicTypeCaption1.semibold() : UIFont.dynamicTypeCaption1
            authorLabel.textColor = isDefaultStickerPack ? Theme.accentBlueColor : Theme.secondaryTextAndIconColor
            authorLabel.lineBreakMode = .byTruncatingTail
            authorViews.append(authorLabel)
        }

        if authorViews.count > 0 {
            let authorStack = UIStackView(arrangedSubviews: authorViews)
            authorStack.axis = .horizontal
            authorStack.alignment = .center
            authorStack.spacing = 4
            textStack.addArrangedSubview(authorStack)
        }

        var subviews: [UIView] = [
            iconView,
            textStack
        ]

        if let actionIconName = actionIconName {
            let actionButton = StickerPackActionButton(actionIconName: actionIconName, block: block)
            subviews.append(actionButton)
        }

        let stack = UIStackView(arrangedSubviews: subviews)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = iconSpacing

        cell.contentView.addSubview(stack)
        stack.autoPinEdgesToSuperviewMargins()

        return cell
    }

    private func imageView(forStickerInfo stickerInfo: StickerInfo,
                           dataSource: StickerPackDataSource) -> UIView? {
        StickerView.stickerView(forStickerInfo: stickerInfo, dataSource: dataSource)
    }

    private func buildEmptySectionItem(labelText: String) -> OWSTableItem {
        return OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                return UITableViewCell()
            }
            return self.buildEmptySectionCell(labelText: labelText)
            })
    }

    private func buildEmptySectionCell(labelText: String) -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        let label = UILabel()
        label.text = labelText
        label.font = UIFont.dynamicTypeCaption1
        label.textColor = Theme.secondaryTextAndIconColor
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setCompressionResistanceHigh()
        label.setContentHuggingHigh()
        cell.contentView.addSubview(label)
        label.autoPinEdgesToSuperviewMargins()

        return cell
    }

    // MARK: Events

    private func show(packInfo: StickerPackInfo) {
        AssertIsOnMainThread()

        Logger.verbose("")

        let packView = StickerPackViewController(stickerPackInfo: packInfo)
        packView.present(from: self, animated: true)
    }

    // We need to retain a link to the send flow during the send flow.
    private var sendMessageFlow: SendMessageFlow?

    private func share(packInfo: StickerPackInfo) {
        AssertIsOnMainThread()

        Logger.verbose("")

        let packUrl = packInfo.shareUrl()

        guard let navigationController = self.navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }
        let messageBody = MessageBody(text: packUrl, ranges: .empty)
        let unapprovedContent = SendMessageUnapprovedContent.text(messageBody: messageBody)
        let sendMessageFlow = SendMessageFlow(flowType: .`default`,
                                              unapprovedContent: unapprovedContent,
                                              useConversationComposeForSingleRecipient: true,
                                              navigationController: navigationController,
                                              delegate: self)
        // Retain the flow until it is complete.
        self.sendMessageFlow = sendMessageFlow
    }

    private func install(stickerPack: StickerPack) {
        AssertIsOnMainThread()

        Logger.verbose("")

        let modalVC = ModalActivityIndicatorViewController(canCancel: false, presentationDelay: 0)
        modalVC.modalPresentationStyle = .overFullScreen
        present(modalVC, animated: false, completion: nil)

        // This will be dismissed once we receive a sticker pack update notification from StickerManager
        pendingModalVC = modalVC
        self.databaseStorage.asyncWrite { transaction in
            StickerManager.installStickerPack(stickerPack: stickerPack,
                                              wasLocallyInitiated: true,
                                              transaction: transaction)
        }

        // or... if 6s have passed. just to be safe.
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(6)) { [weak self] in
            // If the current modal isn't the one we created, we can ignore it
            guard modalVC == self?.pendingModalVC else { return }

            if self?.reachabilityManager.isReachable == true {
                owsFailDebug("Expected to hear back from StickerManager about a newly installed sticker pack")
            }
            self?.updateState()
        }
    }

    @objc
    func packsDidChange() {
        AssertIsOnMainThread()

        Logger.verbose("")

        needsStateUpdate = true
    }

    @objc
    private func didPressDismiss(sender: UIButton) {
        AssertIsOnMainThread()

        Logger.verbose("")

        dismiss(animated: true)
    }
}

// MARK: -

extension ManageStickersViewController: StickerPackDataSourceDelegate {
    public func stickerPackDataDidChange() {
        AssertIsOnMainThread()
        needsTableUpdate = true
    }
}

// MARK: -

extension ManageStickersViewController: SendMessageDelegate {

    public func sendMessageFlowDidComplete(threads: [TSThread]) {
        AssertIsOnMainThread()

        sendMessageFlow = nil

        navigationController?.popToViewController(self, animated: true)
    }

    public func sendMessageFlowDidCancel() {
        AssertIsOnMainThread()

        sendMessageFlow = nil

        navigationController?.popToViewController(self, animated: true)
    }
}

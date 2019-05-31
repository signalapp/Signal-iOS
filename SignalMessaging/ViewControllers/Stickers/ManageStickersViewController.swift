//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import YYImage

private class StickerPackActionButton: UIView {

    private let block: () -> Void

    @available(*, unavailable, message:"use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
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
        actionCircleView.backgroundColor = Theme.offBackgroundColor
        let actionIcon = UIImage(named: actionIconName)?.withRenderingMode(.alwaysTemplate)
        let actionIconView = UIImageView(image: actionIcon)
        actionIconView.tintColor = Theme.secondaryColor
        actionCircleView.addSubview(actionIconView)
        actionIconView.autoCenterInSuperview()
        actionIconView.autoSetDimensions(to: CGSize(width: actionIconSize, height: actionIconSize))

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

@objc
public class ManageStickersViewController: OWSTableViewController {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var stickerManager: StickerManager {
        return SSKEnvironment.shared.stickerManager
    }

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    public required override init() {
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - View Lifecycle

    override public func loadView() {
        super.loadView()

        navigationItem.title = NSLocalizedString("STICKERS_MANAGE_VIEW_TITLE", comment: "Title for the 'manage stickers' view.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(didPressDismiss))

        if FeatureFlags.stickerPackOrdering {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(didPressEditButton))
        }
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.stickersOrPacksDidChange,
                                               object: nil)

        updateState()

        StickerManager.refreshContents()
    }

    private var installedStickerPackSources = [StickerPackDataSource]()
    private var availableBuiltInStickerPackSources = [StickerPackDataSource]()
    private var knownStickerPackSources = [StickerPackDataSource]()

    private func updateState() {
        // We need to recyle data sources to maintain continuity.
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
        updateMapWithOldSources(&oldInstalledSources, availableBuiltInStickerPackSources)
        updateMapWithOldSources(&oldTransientSources, knownStickerPackSources)
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
            let installedStickerPacks = packsWithCovers.filter { $0.isInstalled }
            let availableBuiltInStickerPacks = packsWithCovers.filter { !$0.isInstalled && StickerManager.isDefaultStickerPack($0.info) }
            self.installedStickerPackSources = installedStickerPacks.sorted {
                $0.dateCreated > $1.dateCreated
                }.map { installedSource($0.info) }
            let sortAvailablePacks = { (pack0: StickerPack, pack1: StickerPack) -> Bool in
                return pack0.dateCreated > pack1.dateCreated
            }
            self.availableBuiltInStickerPackSources = availableBuiltInStickerPacks.sorted(by: sortAvailablePacks)
            .map { installedSource($0.info) }

            let sortKnownPacks = { (pack0: KnownStickerPack, pack1: KnownStickerPack) -> Bool in
                return pack0.dateCreated > pack1.dateCreated
            }
            let allKnownStickerPacks = StickerManager.allKnownStickerPacks(transaction: transaction)
            let availableKnownStickerPacks = allKnownStickerPacks.filter { !allPackInfos.contains($0.info) }
            self.knownStickerPackSources = availableKnownStickerPacks.sorted(by: sortKnownPacks)
                .map { transientSource($0.info) }
        }

        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let installedSection = OWSTableSection()
        installedSection.headerTitle = NSLocalizedString("STICKERS_MANAGE_VIEW_INSTALLED_PACKS_SECTION_TITLE", comment: "Title for the 'installed stickers' section of the 'manage stickers' view.")
        if installedStickerPackSources.count < 1 {
            installedSection.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    return UITableViewCell()
                }
                let text = NSLocalizedString("STICKERS_MANAGE_VIEW_NO_INSTALLED_PACKS", comment: "Label indicating that the user has no installed sticker packs.")
                return self.buildEmptySectionCell(labelText: text)
                },
                                              customRowHeight: UITableView.automaticDimension))
        }
        for dataSource in installedStickerPackSources {
            installedSection.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    return UITableViewCell()
                }
                return self.buildTableCell(installedStickerPack: dataSource)
                },
                                     customRowHeight: UITableView.automaticDimension,
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
                         customRowHeight: UITableView.automaticDimension,
                         actionBlock: { [weak self] in
                            guard let packInfo = dataSource.info else {
                                owsFailDebug("Source missing info.")
                                return
                            }
                            self?.show(packInfo: packInfo)
            })
        }

        // Hide known sticker packs until their manifest is available.
        let availableKnownStickerPackSources = knownStickerPackSources.filter { $0.getStickerPack() != nil }
        if availableBuiltInStickerPackSources.count > 0 {
            let section = OWSTableSection()
            section.headerTitle = NSLocalizedString("STICKERS_MANAGE_VIEW_AVAILABLE_BUILT_IN_PACKS_SECTION_TITLE", comment: "Title for the 'available built-in stickers' section of the 'manage stickers' view.")
            for dataSource in availableBuiltInStickerPackSources {
                section.add(itemForAvailablePack(dataSource))
            }
            contents.addSection(section)
        }

        let knownSection = OWSTableSection()
        knownSection.headerTitle = NSLocalizedString("STICKERS_MANAGE_VIEW_AVAILABLE_KNOWN_PACKS_SECTION_TITLE", comment: "Title for the 'available known stickers' section of the 'manage stickers' view.")
        if availableKnownStickerPackSources.count < 1 {
            knownSection.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    return UITableViewCell()
                }
                let text = NSLocalizedString("STICKERS_MANAGE_VIEW_NO_KNOWN_PACKS", comment: "Label indicating that the user has no known sticker packs.")
                return self.buildEmptySectionCell(labelText: text)
                },
                                          customRowHeight: UITableView.automaticDimension))
        }
        for dataSource in availableKnownStickerPackSources {
            knownSection.add(itemForAvailablePack(dataSource))
        }
        contents.addSection(knownSection)

        self.contents = contents
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
            let actionIconName = "download-filled-24"
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

    private func buildTableCell(dataSource: StickerPackDataSource,
                                actionIconName: String?,
                                block: @escaping () -> Void) -> UITableViewCell {

        let cell = OWSTableItem.newCell()

        guard let packInfo = dataSource.info else {
            owsFailDebug("Source missing info.")
            return cell
        }

        let stickerInfo: StickerInfo? = dataSource.installedCoverInfo
        let titleValue: String? = dataSource.title
        let authorNameValue: String? = dataSource.author

        let iconView: UIView
        if let stickerInfo = stickerInfo,
            let coverView = imageView(forStickerInfo: stickerInfo,
                                      dataSource: dataSource) {
            iconView = coverView
        } else {
            iconView = UIView()
        }
        let iconSize: CGFloat = 64
        iconView.autoSetDimensions(to: CGSize(width: iconSize, height: iconSize))

        let title: String
        if let titleValue = titleValue?.ows_stripped(),
            titleValue.count > 0 {
            title = titleValue
        } else {
            title = NSLocalizedString("STICKERS_PACK_DEFAULT_TITLE", comment: "Default title for sticker packs.")
        }
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.ows_dynamicTypeBody.ows_mediumWeight()
        titleLabel.textColor = Theme.primaryColor
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

        let isDefaultStickerPack = StickerManager.isDefaultStickerPack(packInfo)

        var authorViews = [UIView]()
        if isDefaultStickerPack {
            let builtInPackView = UIImageView()
            builtInPackView.setTemplateImageName("check-circle-filled-16", tintColor: UIColor.ows_signalBrandBlue)
            builtInPackView.setCompressionResistanceHigh()
            builtInPackView.setContentHuggingHigh()
            authorViews.append(builtInPackView)
        }

        if let authorName = authorNameValue?.ows_stripped(),
            authorName.count > 0 {
            let authorLabel = UILabel()
            authorLabel.text = authorName
            authorLabel.font = isDefaultStickerPack ? UIFont.ows_dynamicTypeCaption1.ows_mediumWeight() : UIFont.ows_dynamicTypeCaption1
            authorLabel.textColor = isDefaultStickerPack ? UIColor.ows_signalBlue : Theme.secondaryColor
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
        stack.spacing = 12

        cell.contentView.addSubview(stack)
        stack.ows_autoPinToSuperviewMargins()

        return cell
    }

    private func imageView(forStickerInfo stickerInfo: StickerInfo,
                           dataSource: StickerPackDataSource) -> UIView? {

        guard let filePath = dataSource.filePath(forSticker: stickerInfo) else {
            owsFailDebug("Missing sticker data file path.")
            return nil
        }
        guard NSData.ows_isValidImage(atPath: filePath, mimeType: OWSMimeTypeImageWebp) else {
            owsFailDebug("Invalid sticker.")
            return nil
        }
        guard let stickerImage = YYImage(contentsOfFile: filePath) else {
            owsFailDebug("Sticker could not be parsed.")
            return nil
        }

        let stickerView = YYAnimatedImageView()
        stickerView.image = stickerImage
        return stickerView
    }

    private func buildEmptySectionCell(labelText: String) -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        let bubbleView = UIView()
        bubbleView.backgroundColor = Theme.offBackgroundColor
        bubbleView.layer.cornerRadius = 8

        let label = UILabel()
        label.text = labelText
        label.font = UIFont.ows_dynamicTypeCaption1
        label.textColor = Theme.secondaryColor
        label.textAlignment = .center
        bubbleView.addSubview(label)
        label.autoPinHeightToSuperview(withMargin: 24)
        label.autoPinWidthToSuperview(withMargin: 16)

        cell.contentView.addSubview(bubbleView)
        bubbleView.ows_autoPinToSuperviewMargins()

        return cell
    }

    // MARK: Events

    private func show(packInfo: StickerPackInfo) {
        AssertIsOnMainThread()

        Logger.verbose("")

        let packView = StickerPackViewController(stickerPackInfo: packInfo)
        present(packView, animated: true)
    }

    private func share(packInfo: StickerPackInfo) {
        AssertIsOnMainThread()

        Logger.verbose("")

        StickerSharingViewController.shareStickerPack(packInfo, from: self)
    }

    private func install(stickerPack: StickerPack) {
        AssertIsOnMainThread()

        Logger.verbose("")

        databaseStorage.write { (transaction) in
            StickerManager.installStickerPack(stickerPack: stickerPack,
                                              transaction: transaction)
        }
    }

    @objc func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        Logger.verbose("")

        updateState()
    }

    @objc
    private func didPressEditButton(sender: UIButton) {
        AssertIsOnMainThread()

        Logger.verbose("")

        // TODO:
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

        updateTableContents()
    }
}

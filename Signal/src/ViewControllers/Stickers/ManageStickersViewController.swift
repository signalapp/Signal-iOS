//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

private class StickerPackActionButton: UIView {

    private let block: () -> Void

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(actionIconName: String, actionIconTint: UIColor, block: @escaping () -> Void) {
        self.block = block

        super.init(frame: .zero)

        configure(actionIconName: actionIconName, actionIconTint: actionIconTint)
    }

    private func configure(actionIconName: String, actionIconTint: UIColor) {
        let actionIconSize: CGFloat = 20
        let actionCircleSize: CGFloat = 32
        let actionCircleView = CircleView(diameter: actionCircleSize)
        actionCircleView.backgroundColor = .Signal.secondaryFill
        let actionIcon = UIImage(named: actionIconName)?.withRenderingMode(.alwaysTemplate)
        let actionIconView = UIImageView(image: actionIcon)
        actionIconView.tintColor = actionIconTint
        actionCircleView.addSubview(actionIconView)
        actionIconView.autoCenterInSuperview()
        actionIconView.autoSetDimensions(to: CGSize(square: actionIconSize))

        self.addSubview(actionCircleView)
        actionCircleView.autoPinEdgesToSuperviewEdges()

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapButton)))
    }

    @objc
    func didTapButton(sender: UIGestureRecognizer) {
        block()
    }
}

class ManageStickersViewController: OWSTableViewController2, SendMessageDelegate, StickerPackDataSourceDelegate {

    typealias DatedStickerPackInfo = StickerManager.DatedStickerPackInfo

    let stickerManager: StickerManager
    let db: DB

    override convenience init() {
        self.init(
            stickerManager: DependenciesBridge.shared.stickerManager,
            db: DependenciesBridge.shared.db,
        )
    }

    init(stickerManager: StickerManager, db: DB) {
        self.stickerManager = stickerManager
        self.db = db

        super.init()
    }

    // MARK: - View Lifecycle

    override var navbarBackgroundColorOverride: UIColor? { cellBackgroundColor }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = OWSLocalizedString("STICKERS_MANAGE_VIEW_TITLE", comment: "Title for the 'manage stickers' view.")
        navigationItem.titleView = filterPicker
        navigationItem.rightBarButtonItem = .cancelButton(dismissingFrom: self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(packsDidChange),
            name: StickerManager.packsDidChange,
            object: nil,
        )

        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        backgroundStyle = .none
        tableView.backgroundColor = cellBackgroundColor
        defaultSeparatorInsetLeading = hInnerMargin + iconSize + iconSpacing

        updateState()

        stickerManager.downloadPendingStickerPacks()
    }

    private var pendingModalVC: ModalActivityIndicatorViewController?

    private var isShowingAllPacks = false

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
        DebouncedEvents.build(
            mode: .firstLast,
            maxFrequencySeconds: 0.75,
            onQueue: .main,
            notifyBlock: { [weak self] in
                guard let self else { return }
                if self.needsStateUpdate {
                    self.updateState()
                } else if self.needsTableUpdate {
                    self.buildTable()
                }
            },
        )
    }()

    // MARK: - Tab picker

    private enum FilterMode: Int {
        case all = 0
        case installed = 1
    }

    private lazy var filterPicker: UISegmentedControl = {
        let segmentedControl = UISegmentedControl(items: [
            OWSLocalizedString(
                "STICKERS_MANAGE_VIEW_FILTER_TAB_ALL",
                comment: "An option in the sticker management screen allowing the user to select the filter option 'all'; i.e., 'unfiltered'.",
            ),
            OWSLocalizedString(
                "STICKERS_MANAGE_VIEW_FILTER_TAB_MY_STICKERS",
                comment: "An option in the sticker management screen allowing the user to select the filter option 'my stickers'; i.e., their installed packs.",
            ),
        ])
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addAction(
            UIAction { [weak self] _ in self?.filterChanged() },
            for: .valueChanged,
        )
        return segmentedControl
    }()

    private func filterChanged() {
        needsTableUpdate = true
    }

    private func setFilterMode(mode: FilterMode) {
        filterPicker.selectedSegmentIndex = mode.rawValue
        filterChanged()
    }

    private var currentFilterMode: FilterMode {
        FilterMode(rawValue: filterPicker.selectedSegmentIndex) ?? .all
    }

    // MARK: Search

    private let searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.hidesNavigationBarDuringPresentation = false
        controller.searchBar.placeholder = OWSLocalizedString(
            "STICKERS_MANAGE_SEARCH_BAR_PLACEHOLDER",
            comment: "Placeholder text for the search bar in the sticker pack management.",
        )
        return controller
    }()

    private var searchText: String {
        searchController.searchBar.text?.stripped ?? ""
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    // MARK: -

    private var installedStickerPackSources = [StickerPackDataSource]()
    private var defaultStickerPackSources = [StickerPackDataSource]()
    // Includes known and installed sticker pack sources
    private var nonDefaultStickerPackSources = [StickerPackDataSource]()

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
        updateMapWithOldSources(&oldTransientSources, defaultStickerPackSources)
        updateMapWithOldSources(&oldTransientSources, nonDefaultStickerPackSources)

        var installedStickerPacks = [StickerPackRecord]()
        var defaultStickerPacks = [StickerPackRecord]()
        var nonDefaultStickerPacks = [DatedStickerPackInfo]()
        db.read { transaction in
            let allPacks = stickerManager.allStickerPacks(transaction: transaction)
            let allPackInfos = allPacks.map { $0.info }

            // Only show packs with installed covers.
            let packsWithCovers = allPacks.filter {
                stickerManager.isStickerInstalled(stickerInfo: $0.coverInfo, transaction: transaction)
            }
            // Sort sticker packs by "date saved, descending" so that we feature
            // packs that the user has just learned about.
            installedStickerPacks = packsWithCovers.filter { $0.isInstalled }
            defaultStickerPacks = packsWithCovers.filter {
                StickerManager.isDefaultStickerPack(packId: $0.info.packId)
            }

            let installedPacksWithoutDefaults = installedStickerPacks.filter { !StickerManager.isDefaultStickerPack(packId: $0.info.packId) }
            let installedPacksWithDate = stickerManager.mapDatedStickerPacks(stickerPacks: installedPacksWithoutDefaults)
            let knownStickerPackFromMessages = stickerManager.knownStickerPacksFromMessages(transaction: transaction)
            nonDefaultStickerPacks = knownStickerPackFromMessages.filter { !allPackInfos.contains($0.info) } + installedPacksWithDate
        }

        let installedSource = { (info: StickerPackInfo) -> StickerPackDataSource in
            if let source = oldInstalledSources[info] {
                return source
            }
            let source = InstalledStickerPackDataSource(
                stickerPackInfo: info,
                stickerManager: self.stickerManager,
                db: self.db,
            )
            source.add(delegate: self)
            return source
        }
        let transientSource = { (info: StickerPackInfo) -> StickerPackDataSource in
            if let source = oldTransientSources[info] {
                return source
            }
            // Don't download all stickers; we only need covers for this view.
            let source = TransientStickerPackDataSource(
                stickerPackInfo: info,
                shouldDownloadAllStickers: false,
                stickerManager: self.stickerManager,
                db: self.db,
            )
            source.add(delegate: self)
            return source
        }

        self.installedStickerPackSources = installedStickerPacks.sorted {
            $0.dateCreated > $1.dateCreated
        }.map {
            installedSource($0.info)
        }
        self.defaultStickerPackSources = defaultStickerPacks.sorted {
            $0.dateCreated > $1.dateCreated
        }.map {
            transientSource($0.info)
        }
        self.nonDefaultStickerPackSources = nonDefaultStickerPacks.sorted {
            $0.timestamp > $1.timestamp
        }.map {
            transientSource($0.info)
        }

        needsStateUpdate = false
        buildTable()
    }

    private func buildTable(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        let hasResults: Bool
        let searchText = self.searchText

        switch currentFilterMode {
        case .installed:
            let filteredInstalledStickerPackSources = installedStickerPackSources.filter { searchText.isEmpty || $0.title?.filterForDisplay.localizedStandardContains(searchText) == true
            }
            hasResults = !filteredInstalledStickerPackSources.isEmpty
            let installedSection = OWSTableSection()
            for dataSource in filteredInstalledStickerPackSources {
                installedSection.add(OWSTableItem(
                    customCellBlock: { [weak self] in
                        guard let self else {
                            return UITableViewCell()
                        }
                        return self.buildTableCell(installedStickerPack: dataSource, showDownloaded: false)
                    },
                    actionBlock: { [weak self] in
                        guard let packInfo = dataSource.info else {
                            owsFailDebug("Source missing info.")
                            return
                        }
                        self?.show(packInfo: packInfo)
                    },
                    contextMenuActionProvider: contextMenuActionProvider(pack: dataSource),
                ))
            }
            contents.add(installedSection)

        case .all:
            let itemForAvailablePack = { [self] (dataSource: StickerPackDataSource) -> OWSTableItem in
                OWSTableItem(
                    customCellBlock: { [weak self] in
                        guard let self else {
                            return UITableViewCell()
                        }
                        if (dataSource.getStickerPack()?.isInstalled == true) {
                            return self.buildTableCell(installedStickerPack: dataSource, showDownloaded: true)
                        } else {
                            return self.buildTableCell(availableStickerPack: dataSource)
                        }
                    },
                    actionBlock: { [weak self] in
                        guard let packInfo = dataSource.info else {
                            owsFailDebug("Source missing info.")
                            return
                        }
                        self?.show(packInfo: packInfo)
                    },
                    contextMenuActionProvider: contextMenuActionProvider(pack: dataSource),
                )
            }

            let filteredDefaultStickerPackSources = defaultStickerPackSources.filter {
                searchText.isEmpty || $0.title?.filterForDisplay.localizedStandardContains(searchText) == true
            }
            let filteredNonDefaultStickerPackSources = nonDefaultStickerPackSources.filter {
                searchText.isEmpty || $0.title?.filterForDisplay.localizedStandardContains(searchText) == true
            }
            hasResults = !filteredDefaultStickerPackSources.isEmpty || !filteredNonDefaultStickerPackSources.isEmpty
            let maxPacksToPreview = 5
            var packsToRender = filteredDefaultStickerPackSources
            let hasMorePacks = !isShowingAllPacks && packsToRender.count > maxPacksToPreview && !filteredNonDefaultStickerPackSources.isEmpty
            if hasMorePacks {
                packsToRender = Array(packsToRender.prefix(maxPacksToPreview - 1))
            }

            if !packsToRender.isEmpty {
                let section = OWSTableSection()
                section.hasSeparators = true
                section.customHeaderView = {
                    let titleLabel = UILabel.headlineLabel(text: OWSLocalizedString("STICKERS_MANAGE_VIEW_AVAILABLE_BUILT_IN_PACKS_SECTION_TITLE", comment: "Title for the 'available built-in stickers' section of the 'manage stickers' view."), semibold: true)
                    titleLabel.setCompressionResistanceVerticalHigh()
                    let container = UIView()
                    container.addSubview(titleLabel)
                    titleLabel.autoPinEdge(toSuperviewEdge: .leading, withInset: 0)
                    titleLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 0)
                    titleLabel.autoPinEdge(toSuperviewEdge: .top, withInset: (defaultSpacingBetweenSections ?? 0) + 12)
                    titleLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: 10)
                    return container
                }()

                for dataSource in packsToRender {
                    section.add(itemForAvailablePack(dataSource))
                }

                if hasMorePacks {
                    let expandedViewerIndices = (packsToRender.count..<filteredDefaultStickerPackSources.count).map {
                        IndexPath(row: $0, section: contents.sections.count)
                    }

                    section.add(OWSTableItem(
                        customCellBlock: {
                            let cell = OWSTableItem.newCell()
                            cell.preservesSuperviewLayoutMargins = true
                            cell.contentView.preservesSuperviewLayoutMargins = true

                            let iconView = OWSTableItem.buildIconInCircleView(
                                icon: ThemeIcon.chevronDown,
                                iconSize: AvatarBuilder.standardAvatarSizePoints,
                                innerIconSize: 24,
                                iconTintColor: .Signal.label,
                            )

                            let rowLabel = UILabel()
                            rowLabel.text = CommonStrings.seeAllButton
                            rowLabel.textColor = .Signal.label
                            rowLabel.font = OWSTableItem.primaryLabelFont
                            rowLabel.lineBreakMode = .byTruncatingTail

                            let contentRow = UIStackView(arrangedSubviews: [iconView, rowLabel])
                            contentRow.spacing = 16

                            cell.contentView.addSubview(contentRow)

                            contentRow.autoPinEdge(toSuperviewEdge: .leading, withInset: 8)
                            contentRow.autoPinEdge(toSuperviewEdge: .trailing, withInset: 8)
                            contentRow.autoPinEdge(toSuperviewEdge: .top, withInset: Self.cellVInnerMargin)
                            contentRow.autoPinEdge(toSuperviewEdge: .bottom, withInset: Self.cellVInnerMargin)

                            return cell
                        },
                        actionBlock: { [weak self] in
                            self?.showAllPacks(revealingIndices: expandedViewerIndices)
                        },
                    ))
                }

                contents.add(section)
            }

            // Sticker packs whose manifest is available.
            var loadedKnownStickerPackSources = [StickerPackDataSource]()
            // Sticker packs whose manifest is downloading.
            var loadingKnownStickerPackSources = [StickerPackDataSource]()
            // Sticker packs whose manifest download failed permanently.
            var failedKnownStickerPackSources = [StickerPackDataSource]()
            for source in filteredNonDefaultStickerPackSources {
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
                let isFailed = stickerManager.isStickerPackMissing(stickerPackInfo: info)
                if isFailed {
                    failedKnownStickerPackSources.append(source)
                } else {
                    loadingKnownStickerPackSources.append(source)
                }
            }

            if (!filteredNonDefaultStickerPackSources.isEmpty) {
                let knownSection = OWSTableSection()
                knownSection.customHeaderView = {
                    let titleLabel = UILabel.headlineLabel(text: OWSLocalizedString("STICKERS_MANAGE_VIEW_AVAILABLE_KNOWN_PACKS_SECTION_TITLE", comment: "Title for the 'available known stickers' section of the 'manage stickers' view."), semibold: true)
                    titleLabel.setCompressionResistanceVerticalHigh()

                    let subtitleLabel = UILabel()
                    subtitleLabel.text = OWSLocalizedString("STICKERS_MANAGE_VIEW_AVAILABLE_KNOWN_PACKS_SECTION_SUBTITLE", comment: "Subtitle for the section of known stickers in the manage stickers view")
                    subtitleLabel.setCompressionResistanceVerticalHigh()
                    subtitleLabel.textAlignment = .natural
                    subtitleLabel.font = OWSTableViewController2.defaultFooterFont
                    subtitleLabel.textColor = OWSTableViewController2.defaultFooterTextColor
                    subtitleLabel.numberOfLines = 0

                    let introStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
                    introStack.axis = .vertical
                    introStack.spacing = 4
                    introStack.alignment = .leading
                    introStack.isLayoutMarginsRelativeArrangement = true
                    introStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
                        top: (defaultSpacingBetweenSections ?? 0),
                        leading: 0,
                        bottom: 10,
                        trailing: 0,
                    )

                    return introStack
                }()

                for dataSource in loadedKnownStickerPackSources {
                    knownSection.add(itemForAvailablePack(dataSource))
                }
                if !loadingKnownStickerPackSources.isEmpty {
                    let text = OWSLocalizedString(
                        "STICKERS_MANAGE_VIEW_LOADING_KNOWN_PACKS",
                        comment: "Label indicating that one or more known sticker packs is loading.",
                    )
                    knownSection.add(buildEmptySectionItem(labelText: text))
                } else if !failedKnownStickerPackSources.isEmpty {
                    let text = OWSLocalizedString(
                        "STICKERS_MANAGE_VIEW_FAILED_KNOWN_PACKS",
                        comment: "Label indicating that one or more known sticker packs failed to load.",
                    )
                    knownSection.add(buildEmptySectionItem(labelText: text))
                }
                contents.add(knownSection)
            }
        }

        tableView.backgroundView = if (isSearching && !hasResults) {
            emptySearchView
        } else if (currentFilterMode == .installed && !hasResults) {
            emptyStateView
        } else {
            nil
        }

        setContents(contents, shouldReload: shouldReload)
        needsTableUpdate = false
    }

    private func buildTableCell(installedStickerPack dataSource: StickerPackDataSource, showDownloaded: Bool) -> UITableViewCell {
        if (showDownloaded) {
            return buildTableCell(dataSource: dataSource, actionIconName: "check", actionIconTint: UIColor.Signal.tertiaryLabel) {}
        } else {
            return buildTableCell(dataSource: dataSource, actionIconName: nil, actionIconTint: nil) {}
        }
    }

    private func buildTableCell(availableStickerPack dataSource: StickerPackDataSource) -> UITableViewCell {
        if let stickerPack = dataSource.getStickerPack() {
            return buildTableCell(dataSource: dataSource, actionIconName: "plus", actionIconTint: .Signal.label) { [weak self] in
                self?.install(stickerPack: stickerPack)
            }
        } else {
            // Hide "install" button if manifest isn't downloaded yet.
            return buildTableCell(dataSource: dataSource, actionIconName: nil, actionIconTint: nil) { }
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

        guard
            let stickerInfo = dataSource.installedCoverInfo,
            let imageView = imageView(forStickerInfo: stickerInfo, dataSource: dataSource)
        else {
            view.showPlaceholder()
            return view
        }

        view.configure(with: imageView)

        return view
    }

    private let hInnerMargin: CGFloat = 4
    private let iconSize: CGFloat = 56
    private let iconSpacing: CGFloat = 12
    private func buildTableCell(
        dataSource: StickerPackDataSource,
        actionIconName: String?,
        actionIconTint: UIColor?,
        block: @escaping () -> Void,
    ) -> UITableViewCell {

        let cell = OWSTableItem.newCell()

        guard let packInfo = dataSource.info else {
            owsFailDebug("Source missing info.")
            return cell
        }

        let titleValue = dataSource.title?.filterForDisplay
        let authorValue = dataSource.author?.filterForDisplay

        let iconView = reusableCoverView(forDataSource: dataSource) ?? UIView()
        iconView.autoSetDimensions(to: CGSize(square: iconSize))

        var titleViews = [UIView]()
        let title: String
        if let titleValue = titleValue?.ows_stripped(), !titleValue.isEmpty {
            title = titleValue
        } else {
            title = OWSLocalizedString("STICKERS_PACK_DEFAULT_TITLE", comment: "Default title for sticker packs.")
        }
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .dynamicTypeBody
        titleLabel.textColor = .Signal.label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleViews.append(titleLabel)

        let isDefaultStickerPack = StickerManager.isDefaultStickerPack(packId: packInfo.packId)
        if isDefaultStickerPack {
            let builtInPackView = UIImageView()
            builtInPackView.image = .official
            builtInPackView.setCompressionResistanceHigh()
            builtInPackView.setContentHuggingHigh()
            titleViews.append(builtInPackView)
        }

        let titleStack = UIStackView(arrangedSubviews: titleViews)
        titleStack.axis = .horizontal
        titleStack.alignment = .center
        titleStack.spacing = 4

        let textStack = UIStackView(arrangedSubviews: [titleStack])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.setContentHuggingHorizontalLow()
        textStack.setCompressionResistanceHorizontalLow()

        let author: String
        if let authorValue = authorValue?.ows_stripped(), !authorValue.isEmpty {
            author = authorValue
        } else {
            author = OWSLocalizedString("STICKERS_PACK_DEFAULT_AUTHOR", comment: "Default author for sticker packs.")
        }

        let authorLabel = UILabel()
        authorLabel.text = author
        authorLabel.font = UIFont.dynamicTypeCaption1
        authorLabel.textColor = .Signal.secondaryLabel
        authorLabel.lineBreakMode = .byTruncatingTail
        textStack.addArrangedSubview(authorLabel)

        var subviews: [UIView] = [
            iconView,
            textStack,
        ]

        if let actionIconName, let actionIconTint {
            let actionButton = StickerPackActionButton(actionIconName: actionIconName, actionIconTint: actionIconTint, block: block)
            subviews.append(actionButton)
        }

        let stack = UIStackView(arrangedSubviews: subviews)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = iconSpacing

        cell.contentView.addSubview(stack)
        stack.autoPinEdge(toSuperviewEdge: .leading, withInset: hInnerMargin)
        stack.autoPinEdge(toSuperviewEdge: .trailing, withInset: hInnerMargin)
        stack.autoPinEdge(toSuperviewEdge: .top, withInset: Self.cellVInnerMargin)
        stack.autoPinEdge(toSuperviewEdge: .bottom, withInset: Self.cellVInnerMargin)

        return cell
    }

    private func imageView(
        forStickerInfo stickerInfo: StickerInfo,
        dataSource: StickerPackDataSource,
    ) -> UIView? {
        StickerView.stickerView(forStickerInfo: stickerInfo, dataSource: dataSource)
    }

    private func buildEmptySectionItem(labelText: String) -> OWSTableItem {
        return OWSTableItem(customCellBlock: { [weak self] in
            guard let self else {
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
        label.textColor = .Signal.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setCompressionResistanceHigh()
        label.setContentHuggingHigh()
        cell.contentView.addSubview(label)
        label.autoPinEdgesToSuperviewMargins()

        return cell
    }

    private lazy var emptyStateView: UIView = {
        let label = UILabel()
        label.text = OWSLocalizedString("STICKERS_MANAGE_VIEW_NO_INSTALLED_PACKS", comment: "Label indicating that the user has no installed sticker packs.")
        label.font = .dynamicTypeSubheadline
        label.textColor = .Signal.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0

        let button = UIButton(
            configuration: .smallSecondary(title: OWSLocalizedString("STICKERS_MANAGE_VIEW_NO_INSTALLED_PACKS_BUTTON", comment: "Button to redirect back to the manage sticker 'all' section")),
            primaryAction: UIAction { [weak self] _ in self?.setFilterMode(mode: .all) },
        )

        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8

        let container = UIView()
        container.addSubview(stack)
        stack.autoCenterInSuperview()
        stack.autoPinWidthToSuperviewMargins()
        return container
    }()

    private var emptySearchView: UIView {
        let label = UILabel()
        label.text = String(
            format: OWSLocalizedString("STICKERS_MANAGE_SEARCH_NO_RESULTS", comment: "Label for a view explaining that no search results were found. Embeds {{ the search term }}."),
            searchText,
        )
        label.font = .dynamicTypeSubheadline
        label.textColor = .Signal.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0

        let container = UIView()
        container.addSubview(label)
        label.autoCenterInSuperview()
        label.autoPinWidthToSuperviewMargins()
        label.autoPinHeightToSuperviewMargins()
        return container
    }

    // MARK: Context menu

    func contextMenuActionProvider(pack: StickerPackDataSource) -> UIContextMenuActionProvider {
        return { [weak self] _ in
            guard
                let self,
                let stickerPack = pack.getStickerPack()
            else {
                return nil
            }

            let additionalAction = if (stickerPack.isInstalled == true) {
                [self.removeAction(pack: pack)]
            } else {
                [self.addAction(pack: pack)]
            }

            return UIMenu(children: [
                self.sendAction(pack: pack),
                self.copyAction(pack: pack),
            ] + additionalAction)
        }
    }

    private func sendAction(pack: StickerPackDataSource) -> UIAction {
        UIAction(
            title: OWSLocalizedString(
                "STICKERS_MANAGE_VIEW_CONTEXT_MENU_SEND",
                comment: "The title for a context menu item that sends the sticker pack link to someone else.",
            ),
            image: UIImage(named: "forward"),
        ) { [weak self] _ in
            guard let self, let info = pack.info else { return }
            self.share(packInfo: info)
        }
    }

    private func copyAction(pack: StickerPackDataSource) -> UIAction {
        UIAction(
            title: OWSLocalizedString(
                "STICKERS_MANAGE_VIEW_CONTEXT_MENU_COPY",
                comment: "The title for a context menu item that copies the sticker pack link.",
            ),
            image: UIImage(named: "link"),
        ) { [weak self] _ in
            guard let self, let info = pack.info else { return }
            self.copyLinkToPasteboard(packInfo: info)
        }
    }

    private func removeAction(pack: StickerPackDataSource) -> UIAction {
        UIAction(
            title: OWSLocalizedString(
                "STICKERS_MANAGE_VIEW_CONTEXT_MENU_REMOVE",
                comment: "The title for a context menu item that uninstalls a sticker pack.",
            ),
            image: UIImage(named: "minus-circle"),
        ) { [weak self] _ in
            guard let self, let info = pack.info else { return }
            self.didTapUninstall(pack: info)
        }
    }

    private func addAction(pack: StickerPackDataSource) -> UIAction {
        UIAction(
            title: OWSLocalizedString(
                "STICKERS_MANAGE_VIEW_CONTEXT_MENU_ADD",
                comment: "The title for a context menu item that installs a sticker pack.",
            ),
            image: UIImage(named: "plus-circle"),
        ) { [weak self] _ in
            guard let self, let stickerPack = pack.getStickerPack() else { return }
            self.install(stickerPack: stickerPack)
        }
    }

    // MARK: Events

    private func show(packInfo: StickerPackInfo) {
        AssertIsOnMainThread()

        let packView = StickerPackViewController(stickerPackInfo: packInfo)
        packView.present(from: self, animated: true)
    }

    // We need to retain a link to the send flow during the send flow.
    private var sendMessageFlow: SendMessageFlow?

    private func share(packInfo: StickerPackInfo) {
        AssertIsOnMainThread()

        let packUrl = packInfo.shareUrl()

        guard let navigationController = self.navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }
        let messageBody = MessageBody(text: packUrl, ranges: .empty)
        guard let unapprovedContent = SendMessageUnapprovedContent(messageBody: messageBody) else {
            owsFailDebug("Missing messageBody.")
            return
        }
        let sendMessageFlow = SendMessageFlow(
            unapprovedContent: unapprovedContent,
            presentationStyle: .pushOnto(navigationController),
            delegate: self,
        )
        // Retain the flow until it is complete.
        self.sendMessageFlow = sendMessageFlow
    }

    private func install(stickerPack: StickerPackRecord) {
        AssertIsOnMainThread()

        let modalVC = ModalActivityIndicatorViewController(canCancel: false, presentationDelay: 0)
        modalVC.modalPresentationStyle = .overFullScreen
        present(modalVC, animated: false, completion: nil)

        // This will be dismissed once we receive a sticker pack update notification from StickerManager
        pendingModalVC = modalVC
        db.asyncWrite { transaction in
            self.stickerManager.installStickerPack(
                stickerPack: stickerPack,
                wasLocallyInitiated: true,
                transaction: transaction,
            )
        }

        // or... if 6s have passed. just to be safe.
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(6)) { [weak self] in
            // If the current modal isn't the one we created, we can ignore it
            guard modalVC == self?.pendingModalVC else { return }

            if self != nil, SSKEnvironment.shared.reachabilityManagerRef.isReachable {
                owsFailDebug("Expected to hear back from StickerManager about a newly installed sticker pack")
            }
            self?.updateState()
        }
    }

    private func copyLinkToPasteboard(packInfo: StickerPackInfo) {
        UIPasteboard.general.string = packInfo.shareUrl()
        presentToast(
            text: CommonStrings.copiedToClipboardToast,
            image: .copy,
        )
    }

    private func didTapUninstall(pack: StickerPackInfo) {
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
                    self?.didConfirmUninstall(pack: pack)
                },
            ),
        )
        confirmUninstallSheet.addAction(.cancel)
        presentActionSheet(confirmUninstallSheet)
    }

    private func didConfirmUninstall(pack: StickerPackInfo) {
        let stickerPackInfo = pack
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false,
            presentationDelay: 0,
            backgroundBlock: { [db, stickerManager] modal in
                db.write { transaction in
                    stickerManager.uninstallStickerPack(
                        stickerPackInfo: stickerPackInfo,
                        wasLocallyInitiated: true,
                        transaction: transaction,
                    )
                }
                DispatchQueue.main.async {
                    modal.dismiss()
                }
            },
        )
    }

    private func showAllPacks(revealingIndices: [IndexPath]) {
        isShowingAllPacks = true

        if let firstIndex = revealingIndices.first {
            tableView.beginUpdates()

            // Delete the "See All" row.
            tableView.deleteRows(at: [IndexPath(row: firstIndex.row, section: firstIndex.section)], with: .bottom)

            // Insert the new rows.
            tableView.insertRows(at: revealingIndices, with: .top)

            buildTable(shouldReload: false)
            tableView.endUpdates()
        } else {
            buildTable()
        }
    }

    @objc
    func packsDidChange() {
        AssertIsOnMainThread()

        needsStateUpdate = true
    }

    // MARK: - StickerPackDataSourceDelegate

    func stickerPackDataDidChange() {
        AssertIsOnMainThread()
        needsTableUpdate = true
    }

    // MARK: - SendMessageDelegate

    func sendMessageFlowDidComplete(threads: [TSThread]) {
        AssertIsOnMainThread()

        sendMessageFlow = nil

        navigationController?.popToViewController(self, animated: true)
    }

    func sendMessageFlowWillShowConversation() {
        AssertIsOnMainThread()

        sendMessageFlow = nil

        // Don't pop anything -- the flow does that itself.
    }

    func sendMessageFlowDidCancel() {
        AssertIsOnMainThread()

        sendMessageFlow = nil

        navigationController?.popToViewController(self, animated: true)
    }
}

// MARK: - UISearchResultsUpdating

extension ManageStickersViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        needsTableUpdate = true
    }
}

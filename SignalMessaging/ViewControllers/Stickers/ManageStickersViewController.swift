//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

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

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(didPressEditButton))
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.StickersOrPacksDidChange,
                                               object: nil)

        updateState()

        StickerManager.refreshContents()
    }

    private var installedStickerPacks = [StickerPack]()
    private var availableStickerPacks = [StickerPack]()

    private func updateState() {
        self.databaseStorage.read { (transaction) in
            let allPacks = StickerManager.allStickerPacks(transaction: transaction)
            // Only show packs with installed covers.
            let packsWithCovers = allPacks.filter {
                StickerManager.isStickerInstalled(stickerInfo: $0.coverInfo,
                                                  transaction: transaction)
            }
            // Sort sticker packs by "date saved, descending" so that we feature
            // packs that the user has just learned about.
            let installedPacks = packsWithCovers.filter { $0.isInstalled }
            let availablePacks = packsWithCovers.filter { !$0.isInstalled }
            self.installedStickerPacks = installedPacks.sorted {
                $0.dateCreated > $1.dateCreated
            }
            self.availableStickerPacks = availablePacks.sorted {
                // Sort "default" packs before "known" packs.
                let isDefault0 = StickerManager.isDefaultStickerPack($0)
                let isDefault1 = StickerManager.isDefaultStickerPack($1)
                if isDefault0 && !isDefault1 {
                    return true
                }
                if !isDefault0 && isDefault1 {
                    return false
                }
                return $0.dateCreated > $1.dateCreated
            }
        }

        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        // TODO: Sort sticker packs.
        if installedStickerPacks.count > 0 {
            let section = OWSTableSection()
            section.headerTitle = NSLocalizedString("STICKERS_MANAGE_VIEW_INSTALLED_PACKS_SECTION_TITLE", comment: "Title for the 'installed stickers' section of the 'manage stickers' view.")
            for stickerPack in installedStickerPacks {
                section.add(OWSTableItem(customCellBlock: { [weak self] in
                    guard let self = self else {
                        return UITableViewCell()
                    }
                    return self.buildTableCell(installedStickerPack: stickerPack)
                    },
                                         customRowHeight: UITableView.automaticDimension,
                                         actionBlock: { [weak self] in
                                            self?.show(stickerPack: stickerPack)
                }))
            }
            contents.addSection(section)
        }

        // TODO: Sort sticker packs.
        if availableStickerPacks.count > 0 {
            let section = OWSTableSection()
            section.headerTitle = NSLocalizedString("STICKERS_MANAGE_VIEW_AVAILABLE_PACKS_SECTION_TITLE", comment: "Title for the 'available stickers' section of the 'manage stickers' view.")
            for stickerPack in availableStickerPacks {
                section.add(OWSTableItem(customCellBlock: { [weak self] in
                    guard let self = self else {
                        return UITableViewCell()
                    }
                    return self.buildTableCell(availableStickerPack: stickerPack)
                    },
                                         customRowHeight: UITableView.automaticDimension,
                                         actionBlock: { [weak self] in
                                            self?.show(stickerPack: stickerPack)
                }))
            }
            contents.addSection(section)
        }

        self.contents = contents
    }

    private func buildTableCell(installedStickerPack stickerPack: StickerPack) -> UITableViewCell {
        var actionIconName: String?
        if FeatureFlags.stickerPackSharing {
            actionIconName = CurrentAppContext().isRTL ? "reply-filled-24" : "reply-filled-reversed-24"
        }
        return buildTableCell(stickerInfo: stickerPack.coverInfo,
                              title: stickerPack.title,
                              authorName: stickerPack.author,
                              actionIconName: actionIconName) { [weak self] in
                                self?.share(stickerPack: stickerPack)
        }
    }

    private func buildTableCell(availableStickerPack stickerPack: StickerPack) -> UITableViewCell {
        let actionIconName = "download-filled-24"
        return buildTableCell(stickerInfo: stickerPack.coverInfo,
                              title: stickerPack.title,
                              authorName: stickerPack.author,
                              actionIconName: actionIconName) { [weak self] in
                                self?.install(stickerPack: stickerPack)
        }
    }

    private func buildTableCell(stickerInfo: StickerInfo,
                                title titleValue: String?,
                                authorName authorNameValue: String?,
                                actionIconName: String?,
                                block: @escaping () -> Void) -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        let iconView = StickerView(stickerInfo: stickerInfo, size: 64)

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
        textStack.setContentHuggingHorizontalLow()
        textStack.setCompressionResistanceHorizontalLow()

        // TODO: Should we show a default author name?
        if let authorName = authorNameValue?.ows_stripped(),
            authorName.count > 0 {
            let authorLabel = UILabel()
            authorLabel.text = authorName
            authorLabel.font = UIFont.ows_dynamicTypeCaption1
            authorLabel.textColor = Theme.secondaryColor
            authorLabel.lineBreakMode = .byTruncatingTail
            textStack.addArrangedSubview(authorLabel)
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

    // MARK: Events

    private func show(stickerPack: StickerPack) {
        AssertIsOnMainThread()

        Logger.verbose("")

        let packView = StickerPackViewController(stickerPackInfo: stickerPack.info,
                                                 hasDismissButton: false)
        navigationController?.pushViewController(packView, animated: true)
    }

    private func share(stickerPack: StickerPack) {
        AssertIsOnMainThread()

        Logger.verbose("")

        // TODO:
    }

    private func install(stickerPack: StickerPack) {
        AssertIsOnMainThread()

        Logger.verbose("")

        StickerManager.installStickerPack(stickerPack: stickerPack)
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

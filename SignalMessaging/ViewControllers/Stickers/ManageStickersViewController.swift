//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import YYImage
import SignalServiceKit

@objc
public class ManageStickersViewController: OWSTableViewController {

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

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(didPressEditButton))
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.StickersOrPacksDidChange,
                                               object: nil)

        updateState()

        StickerManager.refreshAvailableStickerPacks()
    }

    private var installedStickerPacks = [StickerPack]()
    private var availableStickerPacks = [StickerPack]()

    private func updateState() {
        installedStickerPacks = StickerManager.installedStickerPacks()
        availableStickerPacks = StickerManager.availableStickerPacks()

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
                                            guard let self = self else {
                                                return
                                            }
                                            self.show(stickerPack: stickerPack)
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
                                            guard let self = self else {
                                                return
                                            }
                                            self.install(stickerPack: stickerPack)
                }))
            }
            contents.addSection(section)
        }

        self.contents = contents
    }

    private func buildTableCell(installedStickerPack stickerPack: StickerPack) -> UITableViewCell {
        let iconFilePath = StickerManager.filepathForInstalledSticker(stickerInfo: stickerPack.coverInfo)
        let actionIconName = CurrentAppContext().isRTL ? "reply-filled-24" : "reply-filled-reversed-24"
        return buildTableCell(iconFilePath: iconFilePath,
                              title: stickerPack.title,
                              authorName: stickerPack.author,
                              actionIconName: actionIconName)
    }

    private func buildTableCell(availableStickerPack stickerPack: StickerPack) -> UITableViewCell {
        let iconFilePath = StickerManager.filepathForInstalledSticker(stickerInfo: stickerPack.coverInfo)
        let actionIconName = CurrentAppContext().isRTL ? "reply-filled-24" : "reply-filled-reversed-24"
        return buildTableCell(iconFilePath: iconFilePath,
                              title: stickerPack.title,
                              authorName: stickerPack.author,
                              actionIconName: actionIconName)
    }

    private func buildTableCell(iconFilePath: String?,
                                title titleValue: String?,
                                authorName authorNameValue: String?,
                                actionIconName: String) -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        // TODO: Asset to show while loading a sticker - if any.
        let iconView = YYAnimatedImageView()
        if let iconFilePath = iconFilePath,
            let coverIcon = YYImage(contentsOfFile: iconFilePath) {
            // TODO: This will be webp.
            iconView.image = coverIcon
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

        let actionIconSize: CGFloat = 20
        let actionCircleSize: CGFloat = 32
        let actionCircleView = OWSLayerView(frame: .zero) { (circleView) in
            circleView.backgroundColor = Theme.offBackgroundColor
            circleView.layer.cornerRadius = actionCircleSize * 0.5
        }
        actionCircleView.autoSetDimensions(to: CGSize(width: actionCircleSize, height: actionCircleSize))
        let actionIcon = UIImage(named: actionIconName)?.withRenderingMode(.alwaysTemplate)
        let actionIconView = UIImageView(image: actionIcon)
        actionIconView.tintColor = Theme.secondaryColor
        actionCircleView.addSubview(actionIconView)
        actionIconView.autoCenterInSuperview()
        actionIconView.autoSetDimensions(to: CGSize(width: actionIconSize, height: actionIconSize))

        let stack = UIStackView(arrangedSubviews: [
            iconView,
            textStack,
            actionCircleView
            ])
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

        // TODO:
    }

    private func install(stickerPack: StickerPack) {
        AssertIsOnMainThread()

        Logger.verbose("")

        // TODO:
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
}

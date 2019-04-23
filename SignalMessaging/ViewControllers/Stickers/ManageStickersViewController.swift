//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import YYImage
import SignalServiceKit

@objc
public class ManageStickersViewController: OWSTableViewController {

//        // MARK: - Dependencies
//
//        private var stickerManager: StickerManager {
//            return AppEnvironment.shared.stickerManager
//        }

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // Currently we only use one mode (AttachmentApproval), so we could simplify this class, but it's kind
    // of nice that it's written in a flexible way in case we'd want to use it elsewhere again in the future.
    @objc
    public required override init() {
//        assert(!attachment.hasError)
//        self.attachment = attachment
//        self.mode = mode
        super.init()

        createViews()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Create Views

    private func createViews() {
//        if attachment.isAnimatedImage {
//            createAnimatedPreview()
//        } else if attachment.isImage {
//            createImagePreview()
//        } else if attachment.isVideo {
//            createVideoPreview()
//        } else if attachment.isAudio {
//            createAudioPreview()
//        } else {
//            createGenericPreview()
//        }
    }

//
//    private var hasBegunImport = false
//
//    // MARK: - Dependencies
//
//    private var backup: OWSBackup {
//        return AppEnvironment.shared.backup
//    }

    // MARK: - View Lifecycle

    override public func loadView() {
        super.loadView()

        navigationItem.title = NSLocalizedString("STICKERS_MANAGE_VIEW_TITLE", comment: "Title for the 'manage stickers' view.")
//
//        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didPressCancelButton))
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

//        let section = OWSTableSection()
//
//        section.headerTitle = NSLocalizedString("BACKUP_RESTORE_DECISION_TITLE", comment: "Label for the backup restore decision section.")
////
////        section.add(OWSTableItem.actionItem(withText: NSLocalizedString("CHECK_FOR_BACKUP_RESTORE",
////                                                                        comment: "The label for the 'restore backup' button."), actionBlock: { [weak self] in
////                                                                            guard let strongSelf = self else {
////                                                                                return
////                                                                            }
////                                                                            strongSelf.startImport()
////        }))
//
//        contents.addSection(section)

        self.contents = contents
    }

    private let iconSize = 64

    private func buildTableCell(installedStickerPack stickerPack: StickerPack) -> UITableViewCell {
        let iconFilePath = StickerManager.filepathForInstalledSticker(stickerInfo: stickerPack.coverInfo)
        let actionIconName = CurrentAppContext().isRTL ? "reply-filled-24" : "reply-filled-reversed-24"
        return buildTableCell(iconFilePath: iconFilePath,
                              title: stickerPack.title,
                              authorName: stickerPack.author,
                              actionIconName: actionIconName) { [weak self] in
                                guard let self = self else {
                                    return
                                }
                                self.show(stickerPack: stickerPack)

        }
    }

    private func buildTableCell(availableStickerPack stickerPack: StickerPack) -> UITableViewCell {
        let iconFilePath = StickerManager.filepathForInstalledSticker(stickerInfo: stickerPack.coverInfo)
        let actionIconName = CurrentAppContext().isRTL ? "reply-filled-24" : "reply-filled-reversed-24"
        return buildTableCell(iconFilePath: iconFilePath,
                              title: stickerPack.title,
                              authorName: stickerPack.author,
                              actionIconName: actionIconName) { [weak self] in
                                guard let self = self else {
                                    return
                                }
                                self.install(stickerPack: stickerPack)

        }
    }

    private func buildTableCell(iconFilePath: String?,
                                title titleValue: String?,
                                authorName authorNameValue: String?,
                                actionIconName: String,
                                actionBlock: @escaping () -> Void) -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        // TODO: Asset to show while loading a sticker - if any.
        let iconView = UIImageView()
        if let iconFilePath = iconFilePath,
            let coverIcon = UIImage(contentsOfFile: iconFilePath) {
            // TODO: This will be webp.
            iconView.image = coverIcon
        }

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

        let actionCircleView = OWSLayerView(frame: .zero) { (circleView) in
            circleView.backgroundColor = Theme.offBackgroundColor
            circleView.layer.cornerRadius = min(circleView.width(), circleView.height()) * 0.5
        }
        // TODO: Should this even be a button?  Maybe we should just have the whole row be hot?
        let actionButton = OWSButton(imageName: actionIconName, tintColor: Theme.secondaryColor, block: actionBlock)
        actionCircleView.addSubview(actionButton)
        actionButton.autoPinEdgesToSuperviewEdges()

        let stack = UIStackView(arrangedSubviews: [
            iconView,
            textStack,
            actionCircleView
            ])
        textStack.axis = .horizontal
        textStack.alignment = .center
        textStack.spacing = 12

        cell.contentView.addSubview(stack)
        stack.ows_autoPinToSuperviewMargins()

        return cell
    }

//    private var progressFormatter: NumberFormatter = {
//        let numberFormatter = NumberFormatter()
//        numberFormatter.numberStyle = .percent
//        numberFormatter.maximumFractionDigits = 0
//        numberFormatter.multiplier = 1
//        return numberFormatter
//    }()
//
//    private func updateProgressContents() {
//        let contents = OWSTableContents()
//
//        let section = OWSTableSection()
//
//        section.add(OWSTableItem.label(withText: NSLocalizedString("BACKUP_RESTORE_STATUS", comment: "Label for the backup restore status."), accessoryText: NSStringForBackupImportState(backup.backupImportState)))
//
//        if backup.backupImportState == .inProgress {
//            if let backupImportDescription = backup.backupImportDescription {
//                section.add(OWSTableItem.label(withText: NSLocalizedString("BACKUP_RESTORE_DESCRIPTION", comment: "Label for the backup restore description."), accessoryText: backupImportDescription))
//            }
//
//            if let backupImportProgress = backup.backupImportProgress {
//                let progressInt = backupImportProgress.floatValue * 100
//                if let progressString = progressFormatter.string(from: NSNumber(value: progressInt)) {
//                    section.add(OWSTableItem.label(withText: NSLocalizedString("BACKUP_RESTORE_PROGRESS", comment: "Label for the backup restore progress."), accessoryText: progressString))
//                } else {
//                    owsFailDebug("Could not format progress: \(progressInt)")
//                }
//            }
//        }
//
//        contents.addSection(section)
//        self.contents = contents
//
//        // TODO: Add cancel button.
//    }
//
//    // MARK: Helpers
//
//    @objc
//    private func didPressCancelButton(sender: UIButton) {
//        Logger.info("")
//
//        // TODO: Cancel import.
//
//        cancelAndDismiss()
//    }
//
//    @objc
//    private func cancelAndDismiss() {
//        Logger.info("")
//
//        backup.setHasPendingRestoreDecision(false)
//
//        showHomeView()
//    }
//
//    @objc
//    private func startImport() {
//        Logger.info("")
//
//        hasBegunImport = true
//
//        backup.tryToImport()
//    }
//
//    private func showHomeView() {
//        // In production, this view will never be presented in a modal.
//        // During testing (debug UI, etc.), it may be a modal.
//        let isModal = navigationController?.presentingViewController != nil
//        if isModal {
//            dismiss(animated: true, completion: {
//                SignalApp.shared().showHomeView()
//            })
//        } else {
//            SignalApp.shared().showHomeView()
//        }
//
//        NotificationCenter.default.removeObserver(self)
//    }
//
//    // MARK: - Notifications
//    // MARK: Orientation
//
//    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
//        return .portrait
//    }

  // MARK: Events

    private func show(stickerPack: StickerPack) {
        // TODO:
    }

    private func install(stickerPack: StickerPack) {
        Logger.verbose("")
        // TODO:
    }

    @objc func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        Logger.verbose("")

        updateState()
    }
}

//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SDWebImage
import SignalServiceKit
import SignalUI

protocol EmojiReactorsTableViewDelegate: AnyObject {
    func emojiReactorsTableView(
        _ tableView: EmojiReactorsTableView,
        didTapSticker stickerInfo: StickerInfo
    )
}

class EmojiReactorsTableView: UITableView {
    struct ReactorItem {
        let address: SignalServiceAddress
        let displayName: String
        let emoji: String
        let sticker: CVAttachment?
        let stickerInfo: StickerInfo?
    }

    weak var reactorDelegate: EmojiReactorsTableViewDelegate?
    let stickerImageCache: StickerReactionImageCache

    private var pendingDownloadAttachmentIds = Set<Attachment.IDType>()

    private var reactorItems = [ReactorItem]() {
        didSet { reloadData() }
    }

    init(stickerImageCache: StickerReactionImageCache) {
        self.stickerImageCache = stickerImageCache
        super.init(frame: .zero, style: .plain)

        dataSource = self
        backgroundColor = .clear
        separatorStyle = .none

        register(EmojiReactorCell.self, forCellReuseIdentifier: EmojiReactorCell.reuseIdentifier)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(attachmentDownloadProgress(_:)),
            name: AttachmentDownloads.attachmentDownloadProgressNotification,
            object: nil,
        )
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        for reactions: [OWSReaction],
        stickerAttachmentByReactionId: [Int64: CVAttachment],
        transaction: DBReadTransaction,
    ) {
        pendingDownloadAttachmentIds.removeAll()

        reactorItems = reactions.compactMap { reaction in
            let displayName = SSKEnvironment.shared.contactManagerRef.displayName(for: reaction.reactor, tx: transaction).resolvedValue()

            let sticker: CVAttachment? = reaction.id.flatMap { stickerAttachmentByReactionId[$0] }

            if let sticker, sticker.attachmentStream == nil {
                pendingDownloadAttachmentIds.insert(sticker.attachment.attachment.id)
            }

            return ReactorItem(
                address: reaction.reactor,
                displayName: displayName,
                emoji: reaction.emoji,
                sticker: sticker,
                stickerInfo: reaction.sticker,
            )
        }
    }

    @objc
    private func attachmentDownloadProgress(_ notification: Notification) {
        guard
            let attachmentId = notification
                .userInfo?[AttachmentDownloads.attachmentDownloadAttachmentIDKey]
                as? Attachment.IDType,
            pendingDownloadAttachmentIds.contains(attachmentId),
            let progress = notification
                .userInfo?[AttachmentDownloads.attachmentDownloadProgressKey]
                as? NSNumber,
            progress.floatValue >= 1.0
        else {
            return
        }
        pendingDownloadAttachmentIds.remove(attachmentId)
        reloadData()
    }
}

extension EmojiReactorsTableView: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return reactorItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: EmojiReactorCell.reuseIdentifier, for: indexPath)
        guard let contactCell = cell as? EmojiReactorCell else {
            owsFailDebug("unexpected cell type")
            return cell
        }

        guard let item = reactorItems[safe: indexPath.row] else {
            owsFailDebug("unexpected indexPath")
            return cell
        }

        contactCell.backgroundColor = .clear
        contactCell.configure(item: item, imageCache: stickerImageCache, delegate: self)

        return contactCell
    }
}

extension EmojiReactorsTableView: EmojiReactorCellDelegate {
    fileprivate func emojiReactorCellDidTapSticker(_ cell: EmojiReactorCell) {
        guard
            let indexPath = indexPath(for: cell),
            let item = reactorItems[safe: indexPath.row],
            let stickerInfo = item.stickerInfo
        else { return }
        reactorDelegate?.emojiReactorsTableView(self, didTapSticker: stickerInfo)
    }
}

// MARK: - EmojiReactorCell

private protocol EmojiReactorCellDelegate: AnyObject {
    func emojiReactorCellDidTapSticker(_ cell: EmojiReactorCell)
}

private class EmojiReactorCell: UITableViewCell {
    static let reuseIdentifier = "EmojiReactorCell"

    let avatarView = ConversationAvatarView(sizeClass: .thirtySix, localUserDisplayMode: .asUser)
    let nameLabel = UILabel()
    let emojiLabel = UILabel()
    let stickerImageView = SDAnimatedImageView()
    private static let stickerSize: CGFloat = 36

    weak var delegate: EmojiReactorCellDelegate?

    private var stickerAttachmentId: Attachment.IDType?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none

        layoutMargins = UIEdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)

        contentView.addSubview(avatarView)
        avatarView.autoPinLeadingToSuperviewMargin()
        avatarView.autoVCenterInSuperview()

        contentView.addSubview(nameLabel)
        nameLabel.autoPinLeading(toTrailingEdgeOf: avatarView, offset: 8)
        nameLabel.autoPinHeightToSuperviewMargins()

        emojiLabel.font = .boldSystemFont(ofSize: 24)

        stickerImageView.contentMode = .scaleAspectFit
        stickerImageView.clipsToBounds = true
        stickerImageView.autoSetDimensions(to: CGSize(square: Self.stickerSize))
        stickerImageView.isHidden = true

        let trailingStack = UIStackView(arrangedSubviews: [emojiLabel, stickerImageView])
        trailingStack.axis = .horizontal
        trailingStack.spacing = 0
        contentView.addSubview(trailingStack)
        trailingStack.autoPinLeading(toTrailingEdgeOf: nameLabel, offset: 8)
        trailingStack.setContentHuggingHorizontalHigh()
        trailingStack.autoVCenterInSuperview()
        trailingStack.autoPinTrailingToSuperviewMargin()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapStickerImageView))
        stickerImageView.isUserInteractionEnabled = true
        stickerImageView.addGestureRecognizer(tapGesture)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stickerAttachmentId = nil
        stickerImageView.image = nil
        stickerImageView.isHidden = true
        emojiLabel.isHidden = false
        emojiLabel.text = nil
    }

    func configure(
        item: EmojiReactorsTableView.ReactorItem,
        imageCache: StickerReactionImageCache?,
        delegate: EmojiReactorCellDelegate,
    ) {
        self.delegate = delegate
        nameLabel.textColor = UIColor.Signal.label

        if let sticker = item.sticker, let stream = sticker.attachmentStream, let imageCache {
            let attachmentId = sticker.attachment.attachment.id
            stickerAttachmentId = attachmentId

            Task { [weak self] in
                let image = await imageCache.image(for: stream)
                guard let self, self.stickerAttachmentId == attachmentId else { return }
                if let image {
                    self.applyStickerImage(image)
                }
            }

            // Show emoji as fallback until the async load completes.
            emojiLabel.text = item.emoji
            emojiLabel.isHidden = false
            stickerImageView.isHidden = true
        } else {
            emojiLabel.text = item.emoji
            emojiLabel.isHidden = false
            stickerImageView.isHidden = true
        }

        if item.address.isLocalAddress {
            nameLabel.text = CommonStrings.you
        } else {
            nameLabel.text = item.displayName
        }

        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .address(item.address)
        }
    }

    private func applyStickerImage(_ image: UIImage) {
        stickerImageView.image = image
        stickerImageView.isHidden = false
        emojiLabel.isHidden = true
    }

    @objc
    private func didTapStickerImageView() {
        delegate?.emojiReactorCellDidTapSticker(self)
    }
}

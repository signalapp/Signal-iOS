//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SDWebImage
import SignalServiceKit
public import SignalUI

// MARK: -

public struct EmojiItem {
    // If a specific emoji is not specified, this item represents "all" emoji
    let emoji: String?
    let count: Int
    let sticker: CVAttachment?

    let didSelect: () -> Void

    init(emoji: String?, count: Int, sticker: CVAttachment? = nil, didSelect: @escaping () -> Void) {
        self.emoji = emoji
        self.count = count
        self.sticker = sticker
        self.didSelect = didSelect
    }
}

public class EmojiCountsCollectionView: UICollectionView {

    let itemHeight: CGFloat = 36
    let stickerImageCache: StickerReactionImageCache

    private var pendingDownloadAttachmentIds = Set<Attachment.IDType>()

    public var items = [EmojiItem]() {
        didSet {
            AssertIsOnMainThread()
            updatePendingDownloadAttachmentIds()
            reloadData()
        }
    }

    init(stickerImageCache: StickerReactionImageCache) {
        self.stickerImageCache = stickerImageCache
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.estimatedItemSize = CGSize(square: itemHeight)
        layout.scrollDirection = .horizontal
        super.init(frame: .zero, collectionViewLayout: layout)

        delegate = self
        dataSource = self
        showsHorizontalScrollIndicator = false
        backgroundColor = .clear

        register(EmojiCountCell.self, forCellWithReuseIdentifier: EmojiCountCell.reuseIdentifier)

        contentInset = UIEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        autoSetDimension(.height, toSize: itemHeight + contentInset.top + contentInset.bottom)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(attachmentDownloadProgress(_:)),
            name: AttachmentDownloads.attachmentDownloadProgressNotification,
            object: nil,
        )
    }

    func setSelectedIndex(_ index: Int) {
        selectItem(at: IndexPath(item: index, section: 0), animated: true, scrollPosition: .centeredHorizontally)
    }

    public required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updatePendingDownloadAttachmentIds() {
        pendingDownloadAttachmentIds.removeAll()
        for item in items {
            guard let sticker = item.sticker else { continue }
            if sticker.attachmentStream == nil {
                pendingDownloadAttachmentIds.insert(sticker.attachment.attachment.id)
            }
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

// MARK: - UICollectionViewDelegateFlowLayout

extension EmojiCountsCollectionView: UICollectionViewDelegateFlowLayout {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.debug("")

        guard let item = items[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return
        }

        item.didSelect()
    }
}

// MARK: - UICollectionViewDataSource

extension EmojiCountsCollectionView: UICollectionViewDataSource {

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        return items.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCountCell.reuseIdentifier, for: indexPath)

        guard let item = items[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return cell
        }

        guard let emojiCell = cell as? EmojiCountCell else {
            owsFailDebug("unexpected cell type")
            return cell
        }

        emojiCell.configure(with: item, imageCache: stickerImageCache)

        return emojiCell
    }
}

class EmojiCountCell: UICollectionViewCell {
    let emojiLabel = UILabel()
    let countLabel = UILabel()
    let stickerImageView = SDAnimatedImageView()
    private static let stickerSize: CGFloat = 22

    private var stickerAttachmentId: Attachment.IDType?

    static let reuseIdentifier = "EmojiCountCell"

    override init(frame: CGRect) {
        super.init(frame: .zero)

        let selectedBackground = UIView()
        selectedBackground.backgroundColor = UIColor.Signal.secondaryFill
        selectedBackgroundView = selectedBackground

        stickerImageView.contentMode = .scaleAspectFit
        stickerImageView.clipsToBounds = true
        stickerImageView.autoSetDimensions(to: CGSize(square: Self.stickerSize))
        stickerImageView.isHidden = true

        let stackView = UIStackView(arrangedSubviews: [emojiLabel, stickerImageView, countLabel])
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        stackView.spacing = 4
        contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.autoSetDimension(.height, toSize: 32)

        emojiLabel.font = .systemFont(ofSize: 22)

        countLabel.font = UIFont.dynamicTypeSubheadlineClamped.monospaced().semibold()
        countLabel.textColor = Theme.primaryTextColor
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

    func configure(with item: EmojiItem, imageCache: StickerReactionImageCache?) {
        if let sticker = item.sticker, let stream = sticker.attachmentStream, let imageCache {
            let attachmentId = sticker.attachment.attachment.id
            self.stickerAttachmentId = attachmentId

            Task { [weak self] in
                let image = await imageCache.image(for: stream)
                guard let self, self.stickerAttachmentId == attachmentId else { return }
                if let image {
                    self.applyStickerImage(image)
                }
            }
        } else {
            emojiLabel.text = item.emoji
            emojiLabel.isHidden = item.emoji == nil
            stickerImageView.isHidden = true
        }

        if item.emoji != nil || item.sticker != nil {
            countLabel.text = item.count.abbreviatedString
        } else {
            countLabel.text = String(
                format: OWSLocalizedString(
                    "REACTION_DETAIL_ALL_FORMAT",
                    comment: "The header used to indicate All reactions to a given message. Embeds {{number of reactions}}",
                ),
                item.count.abbreviatedString,
            )
        }
    }

    private func applyStickerImage(_ image: UIImage) {
        stickerImageView.image = image
        stickerImageView.isHidden = false
        emojiLabel.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        selectedBackgroundView?.layer.cornerRadius = height / 2
    }
}

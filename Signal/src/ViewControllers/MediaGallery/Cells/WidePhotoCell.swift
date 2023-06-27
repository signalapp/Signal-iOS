//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

/// This is the collection view cell for "list mode" in All Media.
class WidePhotoCell: MediaTileListModeCell {

    static let reuseIdentifier = "WidePhotoCell"

    private let thumbnailView: ThumbnailView = {
        let thumbnailView = ThumbnailView()
        thumbnailView.autoSetDimensions(to: .square(48))
        return thumbnailView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeSubheadlineClamped
        label.adjustsFontForContentSizeCategory = true
        label.setCompressionResistanceVerticalHigh()
        label.textColor = UIColor(dynamicProvider: { _ in Theme.primaryTextColor })
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeFootnoteClamped
        label.adjustsFontForContentSizeCategory = true
        label.setCompressionResistanceVerticalHigh()
        label.textColor = UIColor(dynamicProvider: { _ in Theme.secondaryTextAndIconColor })
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        let vStack = UIStackView(arrangedSubviews: [ titleLabel, subtitleLabel ])
        vStack.alignment = .leading
        vStack.axis = .vertical
        vStack.spacing = 2

        let hStack = UIStackView(arrangedSubviews: [ thumbnailView, vStack ])
        hStack.alignment = .center
        hStack.axis = .horizontal
        hStack.spacing = 12

        contentView.addSubview(hStack)
        hStack.autoPinHeightToSuperview(withMargin: 8)
        hStack.autoPinTrailingToSuperviewMargin()
        let constraintWithSelectionButton = hStack.leadingAnchor.constraint(equalTo: selectionButton.trailingAnchor, constant: 16)
        let constraintWithoutSelectionButton = hStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)

        separator.autoPinEdge(.leading, to: .leading, of: vStack)

        super.setupViews(constraintWithSelectionButton: constraintWithSelectionButton,
                         constraintWithoutSelectionButton: constraintWithoutSelectionButton)
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        thumbnailView.image = nil
    }

    private func setUpAccessibility(item: PhotoGridItem?) {
        isAccessibilityElement = true

        if let item {
            accessibilityLabel = [
                item.type.localizedString,
                MediaTileDateFormatter.formattedDateString(for: item.mediaMetadata?.creationDate)
            ]
                .compactMap { $0 }
                .joined(separator: ", ")
        } else {
            accessibilityLabel = ""
        }
    }

    override public func makePlaceholder() {
        thumbnailView.image = nil
        setUpAccessibility(item: nil)
    }

    override public func configure(item: MediaGalleryCellItem, spoilerReveal: SpoilerRevealState) {
        switch item {
        case .photoVideo(let photoGridItem):
            super.configure(item: item, spoilerReveal: spoilerReveal)
            configure(photoGridItem)
        default:
            owsFail("Unexpected item type \(item)")
        }
    }

    private var photoGridItem: PhotoGridItem? {
        guard case .photoVideo(let photoGridItem) = item else { return nil }
        return photoGridItem
    }

    private func configure(_ item: PhotoGridItem) {
        // PHCachingImageManager returns multiple progressively better
        // thumbnails in the async block. We want to avoid calling
        // `configure(item:)` multiple times because the high-quality image eventually applied
        // last time it was called will be momentarily replaced by a progression of lower
        // quality images.
        thumbnailView.image = item.asyncThumbnail { [weak self] image in
            guard let self else { return }

            guard let currentItem = self.photoGridItem, currentItem === item else { return }

            if image == nil {
                Logger.debug("image == nil")
            }
            self.thumbnailView.image = image
        }

        if let metadata = item.mediaMetadata {
            titleLabel.text = metadata.sender

            if let date = metadata.formattedDate {
                subtitleLabel.text = "\(metadata.formattedSize) · \(item.type.formattedType) · \(date)"
            } else {
                subtitleLabel.text = "\(metadata.formattedSize) · \(item.type.formattedType)"
            }
        } else {
            titleLabel.text = ""
            subtitleLabel.text = ""
        }
        setUpAccessibility(item: item)
    }

    class func cellHeight() -> CGFloat {
        let measurementCell = WidePhotoCell(frame: CGRect(origin: .zero, size: .square(100)))
        measurementCell.titleLabel.text = "M"
        measurementCell.subtitleLabel.text = "M"
        let cellSize = measurementCell.contentView.systemLayoutSizeFitting(layoutFittingCompressedSize)
        return cellSize.height
    }

    override func mediaPresentationContext(collectionView: UICollectionView, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {

        let presentationFrame = coordinateSpace.convert(thumbnailView.imageView.frame, from: thumbnailView)
        let clippingAreaInsets = UIEdgeInsets(top: collectionView.adjustedContentInset.top, leading: 0, bottom: 0, trailing: 0)

        return MediaPresentationContext(
            mediaView: thumbnailView.imageView,
            presentationFrame: presentationFrame,
            clippingAreaInsets: clippingAreaInsets
        )
    }

    private class ThumbnailView: UIView {

        let imageView: UIImageView = {
            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            imageView.layer.masksToBounds = true
            imageView.layer.cornerRadius = 4
            return imageView
        }()

        var image: UIImage? {
            get { imageView.image }
            set {
                imageView.image = newValue
                setNeedsLayout()
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            addSubview(imageView)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            guard bounds.size.isNonEmpty else { return }

            guard let imageSize = imageView.image?.size else {
                imageView.frame = bounds
                return
            }

            let scaleX = bounds.width / imageSize.width
            let scaleY = bounds.height / imageSize.height
            let scale = min(scaleX, scaleY)
            let thumbnailSize = imageSize * scale
            imageView.frame = CGRect(
                x: 0.5 * (bounds.width - thumbnailSize.width),
                y: 0.5 * (bounds.height - thumbnailSize.height),
                width: thumbnailSize.width,
                height: thumbnailSize.height
            )
        }
    }
}

private extension MediaMetadata {

    var formattedSize: String {
        let byteCount = Int64(byteSize)
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }

    var formattedDate: String? {
        guard let creationDate else {
            return nil
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale.current
        return dateFormatter.string(from: creationDate)
    }
}

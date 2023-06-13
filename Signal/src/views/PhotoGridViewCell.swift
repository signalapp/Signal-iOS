//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI
import UIKit

public enum PhotoGridItemType {
    case photo
    case animated
    case video(Promise<TimeInterval>)

    var localizedString: String {
        switch self {
        case .photo:
            return CommonStrings.attachmentTypePhoto
        case .animated:
            return CommonStrings.attachmentTypeAnimated
        case .video(let promise):
            switch promise.result {
            case .failure, .none:
                return "\(CommonStrings.attachmentTypeVideo)"
            case .success(let value):
                return "\(CommonStrings.attachmentTypeVideo) \(OWSFormat.localizedDurationString(from: value))"
            }
        }
    }

    var formattedType: String {
        switch self {
        case .animated:
            return OWSLocalizedString(
                "ALL_MEDIA_THUMBNAIL_LABEL_GIF",
                comment: "Label shown over thumbnails of GIFs in the All Media view")
        case .photo:
            return OWSLocalizedString(
                "ALL_MEDIA_THUMBNAIL_LABEL_IMAGE",
                comment: "Label shown by thumbnails of images in the All Media view")
        case .video:
            return OWSLocalizedString(
                "ALL_MEDIA_THUMBNAIL_LABEL_VIDEO",
                comment: "Label shown by thumbnails of videos in the All Media view")
        }
    }
}

public enum AllMediaItem {
    case graphic(any PhotoGridItem)
    case audio(AudioItem)

    var attachmentStream: TSAttachmentStream? {
        switch self {
        case .graphic(let photoItem):
            return (photoItem as? GalleryGridCellItem)?.galleryItem.attachmentStream
        case .audio(let audioItem):
            return audioItem.attachmentStream
        }
    }
}

extension AllMediaItem: Equatable {
    public static func == (lhs: AllMediaItem, rhs: AllMediaItem) -> Bool {
        switch (lhs, rhs) {
        case let (.graphic(lvalue), .graphic(rvalue)):
            return lvalue === rvalue
        case let (.audio(lvalue), .audio(rvalue)):
            return lvalue.attachmentStream == rvalue.attachmentStream
        case (.graphic, _), (.audio, _):
            return false
        }
    }
}
public struct AudioItem {
    var message: TSMessage
    var interaction: TSInteraction
    var thread: TSThread
    var attachmentStream: TSAttachmentStream
    var mediaCache: CVMediaCache
    var metadata: MediaMetadata

    var size: UInt {
        UInt(attachmentStream.byteCount)
    }
    var date: Date {
        attachmentStream.creationTimestamp
    }
    var duration: TimeInterval {
        attachmentStream.audioDurationSeconds()
    }

    enum AttachmentType {
        case file
        case voiceMessage
    }
    var attachmentType: AttachmentType {
        let isVoiceMessage = attachmentStream.isVoiceMessageIncludingLegacyMessages
        return isVoiceMessage ? .voiceMessage : .file
    }

    var localizedString: String {
        switch attachmentType {
        case .file:
            return "Audio file"  // ATTACHMENT_TYPE_AUDIO
        case .voiceMessage:
            return "Voice message"  // ATTACHMENT_TYPE_VOICE_MESSAGE
        }
    }
}

public struct MediaMetadata {
    var sender: String
    var abbreviatedSender: String
    var filename: String?
    var byteSize: Int
    var creationDate: Date?
}

public protocol PhotoGridItem: AnyObject {
    var type: PhotoGridItemType { get }
    var isFavorite: Bool { get }
    func asyncThumbnail(completion: @escaping (UIImage?) -> Void) -> UIImage?
    var mediaMetadata: MediaMetadata? { get }
}

public class PhotoGridViewCell: UICollectionViewCell, MediaTileCell {

    static let reuseIdentifier = "PhotoGridViewCell"

    public let imageView: UIImageView

    // Contains icon and shadow.
    private var isFavoriteBadge: UIView?

    private var durationLabel: UILabel?
    private var durationLabelBackground: UIView?
    private let selectionButton = SelectionButton()

    private let highlightedMaskView: UIView
    private let selectedMaskView: UIView

    var item: AllMediaItem?

    private static let selectedBadgeImage = UIImage(named: "media-composer-checkmark")
    public var loadingColor = Theme.washColor
    private(set) var allowsMultipleSelection = false {
        didSet {
            updateSelectionState()
        }
    }

    func setAllowsMultipleSelection(_ allowed: Bool, animated: Bool) {
        allowsMultipleSelection = allowed
    }

    public override var isHighlighted: Bool {
        didSet {
            highlightedMaskView.isHidden = !isHighlighted
        }
    }

    override public var isSelected: Bool {
        didSet {
            updateSelectionState()
        }
    }

    private var isFavorite: Bool = false {
        didSet {
            guard isFavorite else {
                isFavoriteBadge?.isHidden = true
                return
            }
            let badgeIconView: UIView
            if let isFavoriteBadge {
                badgeIconView = isFavoriteBadge
            } else {
                badgeIconView = UIView.container()
                badgeIconView.clipsToBounds = false

                let badgeShadow = GradientView(colors: [ .ows_blackAlpha40, .ows_blackAlpha40, .clear ])
                badgeShadow.gradientLayer.type = .radial
                badgeShadow.gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
                badgeShadow.gradientLayer.endPoint = CGPoint(x: 1, y: 1)
                badgeIconView.addSubview(badgeShadow)

                let badgeIcon = UIImageView(image: Theme.iconImage(.heart16, isDarkThemeEnabled: true).withRenderingMode(.alwaysTemplate))
                badgeIcon.tintColor = .white
                badgeIconView.addSubview(badgeIcon)

                badgeShadow.autoPinEdge(.top, to: .top, of: badgeIcon, withOffset: -20)
                badgeShadow.autoPinEdge(.trailing, to: .trailing, of: badgeIcon, withOffset: 20)
                badgeShadow.centerXAnchor.constraint(equalTo: badgeIconView.leadingAnchor).isActive = true
                badgeShadow.centerYAnchor.constraint(equalTo: badgeIconView.bottomAnchor).isActive = true

                badgeIcon.autoSetDimensions(to: .square(14))
                badgeIcon.autoPinEdge(toSuperviewEdge: .leading, withInset: 6)
                badgeIcon.autoPinEdge(toSuperviewEdge: .top)
                badgeIcon.autoPinEdge(toSuperviewEdge: .trailing)
                badgeIcon.autoPinEdge(toSuperviewEdge: .bottom, withInset: 5)

                contentView.addSubview(badgeIconView)
                badgeIconView.autoPinEdge(toSuperviewEdge: .leading)
                badgeIconView.autoPinEdge(toSuperviewEdge: .bottom)

                isFavoriteBadge = badgeIconView
            }
            badgeIconView.isHidden = false
            contentView.bringSubviewToFront(badgeIconView)
        }
    }

    override init(frame: CGRect) {
        imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill

        highlightedMaskView = UIView()
        highlightedMaskView.alpha = 0.2
        highlightedMaskView.backgroundColor = Theme.darkThemePrimaryColor
        highlightedMaskView.isHidden = true

        selectedMaskView = UIView()
        selectedMaskView.alpha = 0.3
        selectedMaskView.backgroundColor = Theme.darkThemeBackgroundColor
        selectedMaskView.isHidden = true

        super.init(frame: frame)

        clipsToBounds = true

        contentView.addSubview(imageView)
        contentView.addSubview(highlightedMaskView)
        contentView.addSubview(selectedMaskView)
        contentView.addSubview(selectionButton)

        imageView.autoPinEdgesToSuperviewEdges()
        highlightedMaskView.autoPinEdgesToSuperviewEdges()
        selectedMaskView.autoPinEdgesToSuperviewEdges()

        selectionButton.autoPinEdge(toSuperviewEdge: .trailing, withInset: 6)
        selectionButton.autoPinEdge(toSuperviewEdge: .top, withInset: 6)
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func updateSelectionState() {
        selectedMaskView.isHidden = !isSelected
        selectionButton.isSelected = isSelected
        selectionButton.allowsMultipleSelection = allowsMultipleSelection
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if let durationLabel = durationLabel,
           previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            durationLabel.font = Self.durationLabelFont()
        }
    }

    var image: UIImage? {
        get { return imageView.image }
        set {
            imageView.image = newValue
            imageView.backgroundColor = newValue == nil ? loadingColor : .clear
        }
    }

    private static func durationLabelFont() -> UIFont {
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption1)
        return UIFont.semiboldFont(ofSize: max(12, fontDescriptor.pointSize))
    }

    private func setMedia(itemType: PhotoGridItemType) {
        hideVideoDuration()
        switch itemType {
        case .video(let promisedDuration):
            updateVideoDurationWhenPromiseFulfilled(promisedDuration)
        case .animated:
            setCaption(itemType.formattedType)
        case .photo:
            break
        }
    }

    private func updateVideoDurationWhenPromiseFulfilled(_ promisedDuration: Promise<TimeInterval>) {
        let originalItem = item
        promisedDuration.observe { [weak self] result in
            guard let self, self.item == originalItem, case .success(let duration) = result else {
                return
            }
            self.setCaption(OWSFormat.localizedDurationString(from: duration))
        }
    }

    private func hideVideoDuration() {
        durationLabel?.isHidden = true
        durationLabelBackground?.isHidden = true
    }

    private func setCaption(_ caption: String) {
        if durationLabel == nil {
            let durationLabel = UILabel()
            durationLabel.textColor = .white
            durationLabel.font = Self.durationLabelFont()
            durationLabel.layer.shadowColor = UIColor.ows_blackAlpha20.cgColor
            durationLabel.layer.shadowOffset = CGSize(width: -1, height: -1)
            durationLabel.layer.shadowOpacity = 1
            durationLabel.layer.shadowRadius = 4
            durationLabel.shadowOffset = CGSize(width: 0, height: 1)
            durationLabel.adjustsFontForContentSizeCategory = true
            self.durationLabel = durationLabel
        }
        if durationLabelBackground == nil {
            let gradientView = GradientView(from: .clear, to: .ows_blackAlpha60)
            gradientView.gradientLayer.type = .axial
            gradientView.gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
            gradientView.gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
            self.durationLabelBackground = gradientView
        }

        guard let durationLabel = durationLabel, let durationLabelBackground = durationLabelBackground else {
            return
        }

        if durationLabel.superview == nil {
            contentView.addSubview(durationLabel)
            durationLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 6)
            durationLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: 4)
        }
        if durationLabelBackground.superview == nil {
            contentView.insertSubview(durationLabelBackground, belowSubview: durationLabel)
            durationLabelBackground.topAnchor.constraint(equalTo: centerYAnchor).isActive = true
            durationLabelBackground.autoPinEdge(toSuperviewEdge: .leading)
            durationLabelBackground.autoPinEdge(toSuperviewEdge: .trailing)
            durationLabelBackground.autoPinEdge(toSuperviewEdge: .bottom)
        }

        durationLabel.isHidden = false
        durationLabelBackground.isHidden = false
        durationLabel.text = caption
        durationLabel.sizeToFit()

        if let isFavoriteBadge {
            contentView.bringSubviewToFront(isFavoriteBadge)
        }
    }

    private func setUpAccessibility(item: PhotoGridItem?) {
        self.isAccessibilityElement = true

        if let item {
            self.accessibilityLabel = [
                item.type.localizedString,
                MediaTileDateFormatter.formattedDateString(for: item.mediaMetadata?.creationDate)
            ]
                .compactMap { $0 }
                .joined(separator: ", ")
        } else {
            self.accessibilityLabel = ""
        }
    }

    public func makePlaceholder() {
        self.item = nil
        self.image = nil
        setMedia(itemType: .photo)
        setUpAccessibility(item: nil)
    }

    public func configure(item: AllMediaItem, spoilerReveal: SpoilerRevealState) {
        switch item {
        case .graphic(let photoGridItem):
            self.item = item
            reallyConfigure(photoGridItem)
        default:
            owsFailDebug("Unexpected item type \(item)")
        }
    }

    private var photoGridItem: PhotoGridItem? {
        switch item {
        case .graphic(let result):
            return result
        case .none:
            return nil
        default:
            return nil
        }
    }

    private func reallyConfigure(_ item: PhotoGridItem) {
        // PHCachingImageManager returns multiple progressively better
        // thumbnails in the async block. We want to avoid calling
        // `configure(item:)` multiple times because the high-quality image eventually applied
        // last time it was called will be momentarily replaced by a progression of lower
        // quality images.
        image = item.asyncThumbnail { [weak self] image in
            guard let self else { return }

            guard let currentItem = self.photoGridItem else {
                return
            }

            guard currentItem === item else {
                return
            }

            if image == nil {
                Logger.debug("image == nil")
            }
            self.image = image
        }

        isFavorite = item.isFavorite
        setMedia(itemType: item.type)
        isFavorite = item.isFavorite
        setUpAccessibility(item: item)
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        item = nil
        imageView.image = nil
        isFavoriteBadge?.isHidden = true
        durationLabel?.isHidden = true
        durationLabelBackground?.isHidden = true
        highlightedMaskView.isHidden = true
        selectedMaskView.isHidden = true
        selectionButton.reset()
    }

    func mediaPresentationContext(
        collectionView: UICollectionView,
        in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
            guard let mediaSuperview = imageView.superview else {
                owsFailDebug("mediaSuperview was unexpectedly nil")
                return nil
            }
            let presentationFrame = coordinateSpace.convert(imageView.frame, from: mediaSuperview)
            let clippingAreaInsets = UIEdgeInsets(top: collectionView.adjustedContentInset.top, leading: 0, bottom: 0, trailing: 0)
            return MediaPresentationContext(
                mediaView: imageView,
                presentationFrame: presentationFrame,
                clippingAreaInsets: clippingAreaInsets
            )
        }

    func indexPathDidChange(_ indexPath: IndexPath, itemCount: Int) {
    }
}

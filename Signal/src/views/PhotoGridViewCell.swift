//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import SignalUI
import UIKit

public enum PhotoGridItemType {
    case photo, animated, video
}

public protocol PhotoGridItem: AnyObject {
    var type: PhotoGridItemType { get }
    func asyncThumbnail(completion: @escaping (UIImage?) -> Void) -> UIImage?
}

public class PhotoGridViewCell: UICollectionViewCell {

    static let reuseIdentifier = "PhotoGridViewCell"

    public let imageView: UIImageView

    private let contentTypeBadgeView: UIImageView
    private let outlineBadgeView: UIView
    private let selectedBadgeView: UIView

    private let highlightedMaskView: UIView
    private let selectedMaskView: UIView

    var item: PhotoGridItem?

    private static let videoBadgeImage = #imageLiteral(resourceName: "ic_gallery_badge_video")
    private static let animatedBadgeImage = #imageLiteral(resourceName: "ic_gallery_badge_gif")
    private static let selectedBadgeImage = UIImage(named: "media-composer-checkmark")
    public var loadingColor = Theme.washColor

    override public var isSelected: Bool {
        didSet {
            updateSelectionState()
        }
    }

    public var allowsMultipleSelection: Bool = false {
        didSet {
            updateSelectionState()
        }
    }

    func updateSelectionState() {
        if isSelected {
            outlineBadgeView.isHidden = false
            selectedBadgeView.isHidden = false
            selectedMaskView.isHidden = false
        } else if allowsMultipleSelection {
            outlineBadgeView.isHidden = false
            selectedBadgeView.isHidden = true
            selectedMaskView.isHidden = true
        } else {
            outlineBadgeView.isHidden = true
            selectedBadgeView.isHidden = true
            selectedMaskView.isHidden = true
        }
    }

    override public var isHighlighted: Bool {
        didSet {
            self.highlightedMaskView.isHidden = !self.isHighlighted
        }
    }

    override init(frame: CGRect) {
        let selectionBadgeSize: CGFloat = 22
        let contentTypeBadgeSize: CGFloat = 12

        imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill

        contentTypeBadgeView = UIImageView()
        contentTypeBadgeView.isHidden = true

        selectedBadgeView = CircleView(diameter: selectionBadgeSize)
        selectedBadgeView.backgroundColor = .ows_accentBlue
        selectedBadgeView.isHidden = true
        let checkmarkImageView = UIImageView(image: PhotoGridViewCell.selectedBadgeImage)
        checkmarkImageView.tintColor = .white
        selectedBadgeView.addSubview(checkmarkImageView)
        checkmarkImageView.autoCenterInSuperview()

        outlineBadgeView = CircleView()
        outlineBadgeView.backgroundColor = .clear
        outlineBadgeView.layer.borderWidth = 1.5
        outlineBadgeView.layer.borderColor = UIColor.ows_white.cgColor
        selectedBadgeView.isHidden = true

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
        contentView.addSubview(contentTypeBadgeView)
        contentView.addSubview(highlightedMaskView)
        contentView.addSubview(selectedMaskView)
        contentView.addSubview(selectedBadgeView)
        contentView.addSubview(outlineBadgeView)

        imageView.autoPinEdgesToSuperviewEdges()
        highlightedMaskView.autoPinEdgesToSuperviewEdges()
        selectedMaskView.autoPinEdgesToSuperviewEdges()

        // Note assets were rendered to match exactly. We don't want to re-size with
        // content mode lest they become less legible.
        contentTypeBadgeView.autoSetDimensions(to: CGSize(square: contentTypeBadgeSize))
        contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .leading, withInset: 3)
        contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 3)

        outlineBadgeView.autoSetDimensions(to: CGSize(square: selectionBadgeSize))
        outlineBadgeView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 6)
        outlineBadgeView.autoPinEdge(toSuperviewEdge: .top, withInset: 6)

        selectedBadgeView.autoSetDimensions(to: CGSize(square: selectionBadgeSize))
        selectedBadgeView.autoAlignAxis(.vertical, toSameAxisOf: outlineBadgeView)
        selectedBadgeView.autoAlignAxis(.horizontal, toSameAxisOf: outlineBadgeView)
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    var image: UIImage? {
        get { return imageView.image }
        set {
            imageView.image = newValue
            imageView.backgroundColor = newValue == nil ? loadingColor : .clear
        }
    }

    var contentTypeBadgeImage: UIImage? {
        get { return contentTypeBadgeView.image }
        set {
            contentTypeBadgeView.image = newValue
            contentTypeBadgeView.isHidden = newValue == nil
        }
    }

    public func configure(item: PhotoGridItem) {
        self.item = item

        // PHCachingImageManager returns multiple progressively better
        // thumbnails in the async block. We want to avoid calling
        // `configure(item:)` multiple times because the high-quality image eventually applied
        // last time it was called will be momentarily replaced by a progression of lower
        // quality images.
        image = item.asyncThumbnail { [weak self] image in
            guard let self = self else { return }

            guard let currentItem = self.item else {
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

        switch item.type {
        case .video:
            self.contentTypeBadgeImage = PhotoGridViewCell.videoBadgeImage
        case .animated:
            self.contentTypeBadgeImage = PhotoGridViewCell.animatedBadgeImage
        case .photo:
            self.contentTypeBadgeImage = nil
        }
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        item = nil
        imageView.image = nil
        contentTypeBadgeView.isHidden = true
        highlightedMaskView.isHidden = true
        selectedMaskView.isHidden = true
        selectedBadgeView.isHidden = true
        outlineBadgeView.isHidden = true
    }
}

//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

public enum PhotoGridItemType {
    case photo, animated, video
}

public protocol PhotoGridItem: class {
    var type: PhotoGridItemType { get }
    func asyncThumbnail(completion: @escaping (UIImage?) -> Void) -> UIImage?
}

public class PhotoGridViewCell: UICollectionViewCell {

    static let reuseIdentifier = "PhotoGridViewCell"

    public let imageView: UIImageView

    private let contentTypeBadgeView: UIImageView
    private let selectedBadgeView: UIImageView

    private let highlightedView: UIView
    private let selectedView: UIView

    var item: PhotoGridItem?

    private static let videoBadgeImage = #imageLiteral(resourceName: "ic_gallery_badge_video")
    private static let animatedBadgeImage = #imageLiteral(resourceName: "ic_gallery_badge_gif")
    private static let selectedBadgeImage = #imageLiteral(resourceName: "selected_blue_circle")

    public var loadingColor = Theme.offBackgroundColor

    override public var isSelected: Bool {
        didSet {
            self.selectedBadgeView.isHidden = !self.isSelected
            self.selectedView.isHidden = !self.isSelected
        }
    }

    override public var isHighlighted: Bool {
        didSet {
            self.highlightedView.isHidden = !self.isHighlighted
        }
    }

    override init(frame: CGRect) {
        self.imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill

        self.contentTypeBadgeView = UIImageView()
        contentTypeBadgeView.isHidden = true

        self.selectedBadgeView = UIImageView()
        selectedBadgeView.image = PhotoGridViewCell.selectedBadgeImage
        selectedBadgeView.isHidden = true

        self.highlightedView = UIView()
        highlightedView.alpha = 0.2
        highlightedView.backgroundColor = Theme.darkThemePrimaryColor
        highlightedView.isHidden = true

        self.selectedView = UIView()
        selectedView.alpha = 0.3
        selectedView.backgroundColor = Theme.darkThemeBackgroundColor
        selectedView.isHidden = true

        super.init(frame: frame)

        self.clipsToBounds = true

        self.contentView.addSubview(imageView)
        self.contentView.addSubview(contentTypeBadgeView)
        self.contentView.addSubview(highlightedView)
        self.contentView.addSubview(selectedView)
        self.contentView.addSubview(selectedBadgeView)

        imageView.autoPinEdgesToSuperviewEdges()
        highlightedView.autoPinEdgesToSuperviewEdges()
        selectedView.autoPinEdgesToSuperviewEdges()

        // Note assets were rendered to match exactly. We don't want to re-size with
        // content mode lest they become less legible.
        let kContentTypeBadgeSize = CGSize(width: 18, height: 12)
        contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .leading, withInset: 3)
        contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 3)
        contentTypeBadgeView.autoSetDimensions(to: kContentTypeBadgeSize)

        let kSelectedBadgeSize = CGSize(width: 31, height: 31)
        selectedBadgeView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 0)
        selectedBadgeView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 0)
        selectedBadgeView.autoSetDimensions(to: kSelectedBadgeSize)
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

        self.image = item.asyncThumbnail { image in
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

        self.item = nil
        self.imageView.image = nil
        self.contentTypeBadgeView.isHidden = true
        self.highlightedView.isHidden = true
        self.selectedView.isHidden = true
        self.selectedBadgeView.isHidden = true
    }
}

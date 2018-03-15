//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public protocol MediaTileViewControllerDelegate: class {
    func mediaTileViewController(_ viewController: MediaTileViewController, didTapMediaGalleryItem mediaGalleryItem: MediaGalleryItem)
}

public class MediaTileViewController: UICollectionViewController, MediaGalleryCellDelegate {

    // TODO weak?
    private var mediaGalleryDataSource: MediaGalleryDataSource

    private var sections: [GalleryDate: [MediaGalleryItem]] {
        return mediaGalleryDataSource.sections
    }
    private var sectionDates: [GalleryDate] {
        return mediaGalleryDataSource.sectionDates
    }

    private let uiDatabaseConnection: YapDatabaseConnection

    public weak var delegate: MediaTileViewControllerDelegate?

    let kSectionHeaderReuseIdentifier = "kSectionHeaderReuseIdentifier"
    let kCellReuseIdentifier = "kCellReuseIdentifier"

    init(mediaGalleryDataSource: MediaGalleryDataSource, uiDatabaseConnection: YapDatabaseConnection) {

        self.mediaGalleryDataSource = mediaGalleryDataSource
        self.uiDatabaseConnection = uiDatabaseConnection

        // Layout Setup

        let screenWidth = UIScreen.main.bounds.size.width
        let kItemsPerRow = 4
        let kInterItemSpacing: CGFloat = 2

        let availableWidth = screenWidth - CGFloat(kItemsPerRow + 1) * kInterItemSpacing
        let kItemWidth = floor(availableWidth / CGFloat(kItemsPerRow))

        let layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        layout.itemSize = CGSize(width: kItemWidth, height: kItemWidth)
        layout.minimumInteritemSpacing = kInterItemSpacing
        layout.minimumLineSpacing = kInterItemSpacing
        layout.sectionHeadersPinToVisibleBounds = true

        let kHeaderHeight: CGFloat = 50
        layout.headerReferenceSize = CGSize(width: 0, height: kHeaderHeight)

        super.init(collectionViewLayout: layout)

        updateSections()
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: View Lifecycle Overrides

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.title = MediaStrings.allMedia

        guard let collectionView = self.collectionView else {
            owsFail("\(logTag) in \(#function) collectionView was unexpectedly nil")
            return
        }
        collectionView.backgroundColor = UIColor.white
        collectionView.register(MediaGalleryCell.self, forCellWithReuseIdentifier: kCellReuseIdentifier)
        collectionView.register(MediaGallerySectionHeader.self, forSupplementaryViewOfKind: UICollectionElementKindSectionHeader, withReuseIdentifier: kSectionHeaderReuseIdentifier)

        // feels a bit weird to have content smashed all the way to the bottom edge.
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)

        // FIXME: For some reason this is scrolling not *quite* to the bottom in viewDidLoad.
        // It does work in viewDidAppear. What changes?
        self.view.layoutIfNeeded()
        scrollToBottom(animated: false)
    }

    // MARK: UIColletionViewDataSource

    override public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return sections.keys.count
    }

    override public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        guard let sectionDate = self.sectionDates[safe: sectionIdx] else {
            owsFail("\(logTag) in \(#function) unknown section: \(sectionIdx)")
            return 0
        }

        guard let section = self.sections[sectionDate] else {
            owsFail("\(logTag) in \(#function) no section for date: \(sectionDate)")
            return 0
        }

        // We shouldn't show empty sections
        assert(section.count > 0)

        return section.count
    }

    override public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {

        let defaultView = UICollectionReusableView()
        if (kind == UICollectionElementKindSectionHeader) {
            guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kSectionHeaderReuseIdentifier, for: indexPath) as? MediaGallerySectionHeader else {
                owsFail("\(logTag) in \(#function) unable to build section header for indexPath: \(indexPath)")
                return defaultView
            }
            guard let date = self.sectionDates[safe: indexPath.section] else {
                owsFail("\(logTag) in \(#function) unknown section for indexPath: \(indexPath)")
                return defaultView
            }

            sectionHeader.configure(title: date.localizedString)
            return sectionHeader
        }

        return defaultView
    }

    override public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let defaultCell = UICollectionViewCell()

        guard let sectionDate = self.sectionDates[safe: indexPath.section] else {
            owsFail("\(logTag) in \(#function) unknown section: \(indexPath.section)")
            return defaultCell
        }

        guard let section = self.sections[sectionDate] else {
            owsFail("\(logTag) in \(#function) no section for date: \(sectionDate)")
            return defaultCell
        }

        guard let galleryItem = section[safe: indexPath.row] else {
            owsFail("\(logTag) in \(#function) no message for row: \(indexPath.row)")
            return defaultCell
        }

        guard let cell = self.collectionView?.dequeueReusableCell(withReuseIdentifier: kCellReuseIdentifier, for: indexPath) as? MediaGalleryCell else {
            owsFail("\(logTag) in \(#function) unexptected cell for indexPath: \(indexPath)")
            return defaultCell
        }

        cell.configure(item: galleryItem, delegate: self)

        return cell
    }

    // MARK: MediaGalleryDelegate

    public func didTapCell(_ cell: MediaGalleryCell, item: MediaGalleryItem) {
        Logger.debug("\(logTag) in \(#function)")
        self.delegate?.mediaTileViewController(self, didTapMediaGalleryItem: item)
    }

    // MARK: Util

    private func scrollToBottom(animated isAnimated: Bool) {
        guard let collectionView = self.collectionView else {
            owsFail("\(self.logTag) in \(#function) collectionView was unexpectedly nil")
            return
        }

        let yOffset: CGFloat = collectionView.contentSize.height - collectionView.bounds.size.height + collectionView.contentInset.bottom
        let offset: CGPoint  = CGPoint(x: 0, y: yOffset)

        collectionView.setContentOffset(offset, animated: isAnimated)
    }

    // TODO? dbModified? Is this even  necessary?
    private func updateSections() {
        self.collectionView?.reloadData()
    }

}

class MediaGallerySectionHeader: UICollectionReusableView {

    // HACK: scrollbar incorrectly appears *behind* section headers
    // in collection view on iOS11 =(
    private class AlwaysOnTopLayer: CALayer {
        override var zPosition: CGFloat {
            get { return 0 }
            set {}
        }
    }

    let label: UILabel

    override class var layerClass: AnyClass {
        get {
            // HACK: scrollbar incorrectly appears *behind* section headers
            // in collection view on iOS11 =(
            if #available(iOS 11, *) {
                return AlwaysOnTopLayer.self
            } else {
                return super.layerClass
            }
        }
    }

    override init(frame: CGRect) {
        label = UILabel()

        let blurEffect = UIBlurEffect(style: .light)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)

        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        super.init(frame: frame)

        self.addSubview(blurEffectView)
        self.addSubview(label)

        blurEffectView.autoPinEdgesToSuperviewEdges()
        label.autoPinEdge(toSuperviewEdge: .trailing)
        label.autoPinEdge(toSuperviewEdge: .leading, withInset: 10)
        label.autoVCenterInSuperview()
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(title: String) {
        self.label.text = title
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        self.label.text = nil
    }
}

public protocol MediaGalleryCellDelegate: class {
    func didTapCell(_ cell: MediaGalleryCell, item: MediaGalleryItem)
}

public class MediaGalleryCell: UICollectionViewCell {

    private let imageView: UIImageView
    private var tapGesture: UITapGestureRecognizer!

    private var item: MediaGalleryItem?
    public weak var delegate: MediaGalleryCellDelegate?

    override init(frame: CGRect) {
        self.imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill

        super.init(frame: frame)

        self.tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        self.addGestureRecognizer(tapGesture)

        self.clipsToBounds = true
        self.addSubview(imageView)

        imageView.autoPinEdgesToSuperviewEdges()
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(item: MediaGalleryItem, delegate: MediaGalleryCellDelegate) {
        self.item = item
        self.imageView.image = item.image
        self.delegate = delegate
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        self.item = nil
        self.imageView.image = nil
        self.delegate = nil
    }

    // MARK: Events

    func didTap(gestureRecognizer: UITapGestureRecognizer) {
        guard let item = self.item else {
            owsFail("\(logTag) item was unexpectedly nil")
            return
        }

        self.delegate?.didTapCell(self, item: item)
    }
}

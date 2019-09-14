//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import Photos
import PromiseKit

protocol RecentPhotosDelegate: class {
    var isMediaLibraryAccessGranted: Bool { get }
    func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment)
}

class RecentPhotosCollectionView: UICollectionView {
    let maxRecentPhotos = 48

    var isReadyForPhotoLibraryAccess: Bool {
        return recentPhotosDelegate?.isMediaLibraryAccessGranted == true
    }

    var hasPhotos: Bool {
        guard isReadyForPhotoLibraryAccess else { return false }
        return collectionContents.assetCount > 0
    }
    weak var recentPhotosDelegate: RecentPhotosDelegate?

    private var fetchingAttachmentIndex: IndexPath? {
        didSet {
            var indexPaths = [IndexPath]()

            if let oldValue = oldValue {
                indexPaths.append(oldValue)
            }
            if let newValue = fetchingAttachmentIndex {
                indexPaths.append(newValue)
            }

            reloadItems(at: indexPaths)
        }
    }

    private lazy var photoLibrary: PhotoLibrary = {
        let library = PhotoLibrary()
        library.add(delegate: self)
        return library
    }()
    private lazy var collection = photoLibrary.defaultPhotoCollection()
    private lazy var collectionContents = collection.contents(ascending: false, limit: maxRecentPhotos)

    var itemSize: CGSize = .zero {
        didSet {
            guard oldValue != itemSize else { return }
            updateLayout()
        }
    }

    private var photoMediaSize: PhotoMediaSize {
        let size = PhotoMediaSize()
        size.thumbnailSize = itemSize
        return size
    }

    private let collectionViewFlowLayout = UICollectionViewFlowLayout()

    init() {
        super.init(frame: .zero, collectionViewLayout: collectionViewFlowLayout)

        dataSource = self
        delegate = self
        showsHorizontalScrollIndicator = false

        contentInset = UIEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)

        backgroundColor = .clear

        register(RecentPhotoCell.self, forCellWithReuseIdentifier: RecentPhotoCell.reuseIdentifier)

        collectionViewFlowLayout.scrollDirection = .horizontal
        collectionViewFlowLayout.minimumLineSpacing = 6

        updateLayout()
    }

    private func updateLayout() {
        AssertIsOnMainThread()

        // We don't want to do anything until media library permission is granted.
        guard isReadyForPhotoLibraryAccess else { return }
        guard itemSize.height > 0, itemSize.width > 0 else { return }

        collectionViewFlowLayout.itemSize = itemSize
        collectionViewFlowLayout.invalidateLayout()

        reloadData()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension RecentPhotosCollectionView: PhotoLibraryDelegate {
    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary) {
        collectionContents = collection.contents(ascending: false, limit: maxRecentPhotos)
        reloadData()
    }
}

// MARK: - UICollectionViewDelegate

extension RecentPhotosCollectionView: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard fetchingAttachmentIndex == nil else { return }
        fetchingAttachmentIndex = indexPath

        let asset = collectionContents.asset(at: indexPath.item)
        collectionContents.outgoingAttachment(
            for: asset,
            imageQuality: .medium
        ).done { [weak self] attachment in
            self?.recentPhotosDelegate?.didSelectRecentPhoto(asset: asset, attachment: attachment)
        }.ensure { [weak self] in
            self?.fetchingAttachmentIndex = nil
        }.catch { _ in
            OWSAlerts.showAlert(title: NSLocalizedString("IMAGE_PICKER_FAILED_TO_PROCESS_ATTACHMENTS", comment: "alert title"))
        }.retainUntilComplete()
    }
}

// MARK: - UICollectionViewDataSource

extension RecentPhotosCollectionView: UICollectionViewDataSource {

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        guard isReadyForPhotoLibraryAccess else { return 0 }
        return collectionContents.assetCount
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RecentPhotoCell.reuseIdentifier, for: indexPath) as? RecentPhotoCell else {
            owsFail("cell was unexpectedly nil")
        }

        let assetItem = collectionContents.assetItem(at: indexPath.item, photoMediaSize: photoMediaSize)
        cell.configure(item: assetItem, isLoading: fetchingAttachmentIndex == indexPath)
        #if DEBUG
        // These accessibilityIdentifiers won't be stable, but they
        // should work for the purposes of our automated testing.
        cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "recent-photo-\(indexPath.row)")
        #endif
        return cell
    }
}

class RecentPhotoCell: UICollectionViewCell {

    static let reuseIdentifier = "RecentPhotoCell"

    let imageView = UIImageView()
    let contentTypeBadgeView = UIImageView()
    let loadingIndicator = UIActivityIndicatorView(style: .whiteLarge)

    var item: PhotoGridItem?

    override init(frame: CGRect) {

        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        clipsToBounds = true
        layer.cornerRadius = 4

        contentView.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges()

        imageView.addSubview(contentTypeBadgeView)
        contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 3)
        contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 3)
        contentTypeBadgeView.autoSetDimensions(to: CGSize(width: 18, height: 12))

        loadingIndicator.layer.shadowColor = UIColor.black.cgColor
        loadingIndicator.layer.shadowOffset = CGSize(width: 0, height: 0)
        loadingIndicator.layer.shadowOpacity = 0.7
        loadingIndicator.layer.shadowRadius = 3.0

        contentView.addSubview(loadingIndicator)
        loadingIndicator.autoCenterInSuperview()
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    var image: UIImage? {
        get { return imageView.image }
        set {
            imageView.image = newValue
            imageView.backgroundColor = newValue == nil ? Theme.offBackgroundColor : .clear
        }
    }

    var contentTypeBadgeImage: UIImage? {
        get { return contentTypeBadgeView.image }
        set {
            contentTypeBadgeView.image = newValue
            contentTypeBadgeView.isHidden = newValue == nil
        }
    }

    public func configure(item: PhotoGridItem, isLoading: Bool) {
        self.item = item

        image = item.asyncThumbnail { [weak self] image in
            guard let self = self, let currentItem = self.item, currentItem === item else { return }
            self.image = image
        }

        switch item.type {
        case .video:
            self.contentTypeBadgeImage = #imageLiteral(resourceName: "ic_gallery_badge_video")
        case .animated:
            self.contentTypeBadgeImage = #imageLiteral(resourceName: "ic_gallery_badge_gif")
        case .photo:
            self.contentTypeBadgeImage = nil
        }

        if isLoading { startLoading() }
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        item = nil
        imageView.image = nil
        stopLoading()
    }

    func startLoading() {
        loadingIndicator.startAnimating()
    }

    func stopLoading() {
        loadingIndicator.stopAnimating()
    }
}

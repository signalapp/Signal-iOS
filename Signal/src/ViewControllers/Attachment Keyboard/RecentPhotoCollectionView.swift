//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol RecentPhotosDelegate: class {
    var isMediaLibraryAccessGranted: Bool { get }
    func didSelectRecentPhoto(_ attachment: SignalAttachment)
}

class RecentPhotosCollectionView: UICollectionView {
    let maxRecentPhotos = 48

    var hasPhotos: Bool { return collectionContents.assetCount > 0 }
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

    private let photoLibrary = PhotoLibrary()
    private lazy var collection = photoLibrary.defaultPhotoCollection()
    private lazy var collectionContents = collection.contents(ascending: false, limit: maxRecentPhotos)

    private var itemSize: CGSize {
        return CGSize(width: frame.height, height: frame.height)
    }

    private var photoMediaSize: PhotoMediaSize {
        let size = PhotoMediaSize()
        size.thumbnailSize = itemSize
        return size
    }

    private let collectionViewFlowLayout = UICollectionViewFlowLayout()

    override var bounds: CGRect {
        didSet {
            guard oldValue != bounds else { return }
            updateLayout()
        }
    }

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

        photoLibrary.add(delegate: self)

        updateLayout()
    }

    private func updateLayout() {
        AssertIsOnMainThread()

        // We don't want to do anything until media library permission is granted.
        guard recentPhotosDelegate?.isMediaLibraryAccessGranted == true else { return }
        guard frame.height > 0 else { return }

        // The items should always expand to fit the height of the collection view.
        // We'll always just have one row of items.
        collectionViewFlowLayout.itemSize = itemSize
        collectionViewFlowLayout.invalidateLayout()
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

        collectionContents.outgoingAttachment(
            for: collectionContents.asset(at: indexPath.item),
            imageQuality: .medium
        ).done { [weak self] attachment in
            self?.recentPhotosDelegate?.didSelectRecentPhoto(attachment)
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
        return collectionContents.assetCount
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RecentPhotoCell.reuseIdentifier, for: indexPath) as? RecentPhotoCell else {
            owsFail("cell was unexpectedly nil")
        }

        let assetItem = collectionContents.assetItem(at: indexPath.item, photoMediaSize: photoMediaSize)
        cell.configure(item: assetItem, isLoading: fetchingAttachmentIndex == indexPath)
        return cell
    }
}

class RecentPhotoCell: UICollectionViewCell {

    static let reuseIdentifier = "RecentPhotoCell"

    let imageView = UIImageView()
    let loadingIndicator = UIActivityIndicatorView(style: .whiteLarge)

    var item: PhotoGridItem?

    override init(frame: CGRect) {

        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        clipsToBounds = true
        layer.cornerRadius = 4

        contentView.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges()

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

    public func configure(item: PhotoGridItem, isLoading: Bool) {
        self.item = item

        image = item.asyncThumbnail { [weak self] image in
            guard let self = self, let currentItem = self.item, currentItem === item else { return }
            self.image = image
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

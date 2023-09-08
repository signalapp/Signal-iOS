//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import PhotosUI
import SignalMessaging
import SignalUI

protocol RecentPhotosDelegate: AnyObject {
    var isMediaLibraryAccessGranted: Bool { get }
    var isMediaLibraryAccessLimited: Bool { get }
    func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment)
}

class RecentPhotosCollectionView: UICollectionView {
    static let maxRecentPhotos = 96
    static let itemSpacing: CGFloat = 12

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
    private lazy var collection = photoLibrary.defaultPhotoAlbum()
    private lazy var collectionContents = collection.contents(ascending: false, limit: RecentPhotosCollectionView.maxRecentPhotos)

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

    private let collectionViewFlowLayout: UICollectionViewFlowLayout = {
        let layout = RTLEnabledCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = itemSpacing
        layout.minimumInteritemSpacing = itemSpacing
        return layout
    }()

    init() {
        super.init(frame: .zero, collectionViewLayout: collectionViewFlowLayout)

        dataSource = self
        delegate = self

        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        let horizontalInset = OWSTableViewController2.defaultHOuterMargin
        contentInset = UIEdgeInsets(top: 0, leading: horizontalInset, bottom: 0, trailing: horizontalInset)
        register(RecentPhotoCell.self, forCellWithReuseIdentifier: RecentPhotoCell.reuseIdentifier)

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
        collectionContents = collection.contents(ascending: false, limit: RecentPhotosCollectionView.maxRecentPhotos)
        reloadData()
    }
}

// MARK: - UICollectionViewDelegate

extension RecentPhotosCollectionView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard fetchingAttachmentIndex == nil else { return }

        guard indexPath.row < collectionContents.assetCount else {
            owsFailDebug("Asset does not exist.")
            return
        }

        fetchingAttachmentIndex = indexPath

        let asset = collectionContents.asset(at: indexPath.item)
        collectionContents.outgoingAttachment(
            for: asset
        ).done { [weak self] attachment in
            self?.recentPhotosDelegate?.didSelectRecentPhoto(asset: asset, attachment: attachment)
        }.ensure { [weak self] in
            self?.fetchingAttachmentIndex = nil
        }.catch { error in
            Logger.error("Error: \(error)")
            OWSActionSheets.showActionSheet(title: OWSLocalizedString("IMAGE_PICKER_FAILED_TO_PROCESS_ATTACHMENTS", comment: "alert title"))
        }
    }
}

// MARK: - UICollectionViewDataSource

extension RecentPhotosCollectionView: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        guard isReadyForPhotoLibraryAccess else { return 0 }
        return collectionContents.assetCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
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

private class RecentPhotoCell: UICollectionViewCell {

    static let reuseIdentifier = "RecentPhotoCell"

    private let imageView = UIImageView()
    private var contentTypeBadgeView: UIImageView?
    private var durationLabel: UILabel?
    private var durationLabelBackground: UIView?
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    private var item: PhotoGridItem?

    override init(frame: CGRect) {

        super.init(frame: frame)

        clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        contentView.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges()

        loadingIndicator.layer.shadowColor = UIColor.black.cgColor
        loadingIndicator.layer.shadowOffset = .zero
        loadingIndicator.layer.shadowOpacity = 0.7
        loadingIndicator.layer.shadowRadius = 3.0

        contentView.addSubview(loadingIndicator)
        loadingIndicator.autoCenterInSuperview()
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var frame: CGRect {
        didSet {
            updateCornerRadius()
        }
    }

    override var bounds: CGRect {
        didSet {
            updateCornerRadius()
        }
    }

    private func updateCornerRadius() {
        let cellSize = min(bounds.width, bounds.height)
        guard cellSize > 0 else { return }
        layer.cornerRadius = (cellSize * 13 / 84).rounded()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if let durationLabel,
           previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            durationLabel.font = RecentPhotoCell.durationLabelFont()
        }
    }

    private var image: UIImage? {
        get { return imageView.image }
        set {
            imageView.image = newValue
            imageView.backgroundColor = newValue == nil ? Theme.washColor : .clear
        }
    }

    private static func durationLabelFont() -> UIFont {
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption1)
        return UIFont.semiboldFont(ofSize: max(12, fontDescriptor.pointSize))
    }

    private func setContentTypeBadge(image: UIImage?) {
        guard image != nil else {
            contentTypeBadgeView?.isHidden = true
            return
        }

        if contentTypeBadgeView == nil {
            let contentTypeBadgeView = UIImageView()
            contentView.addSubview(contentTypeBadgeView)
            contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 4)
            contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 4)
            self.contentTypeBadgeView = contentTypeBadgeView
        }
        contentTypeBadgeView?.isHidden = false
        contentTypeBadgeView?.image = image
        contentTypeBadgeView?.sizeToFit()
    }

    private func setMedia(itemType: PhotoGridItemType) {
        guard case .video(let promisedDuration) = itemType, let duration = promisedDuration.value else {
            durationLabel?.isHidden = true
            durationLabelBackground?.isHidden = true
            return
        }

        if durationLabel == nil {
            let durationLabel = UILabel()
            durationLabel.textColor = .white
            durationLabel.font = RecentPhotoCell.durationLabelFont()
            durationLabel.layer.shadowColor = UIColor.ows_blackAlpha20.cgColor
            durationLabel.layer.shadowOffset = CGSize(width: -1, height: -1)
            durationLabel.layer.shadowOpacity = 1
            durationLabel.layer.shadowRadius = 4
            durationLabel.shadowOffset = CGSize(width: 0, height: 1)
            durationLabel.adjustsFontForContentSizeCategory = true
            self.durationLabel = durationLabel
        }
        if durationLabelBackground == nil {
            let gradientView = GradientView(from: .ows_blackAlpha40, to: .clear)
            gradientView.gradientLayer.type = .radial
            gradientView.gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradientView.gradientLayer.endPoint = CGPoint(x: 0, y: 90/122) // 122 x 58 oval
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
            durationLabelBackground.autoPinEdge(.top, to: .top, of: durationLabel, withOffset: -10)
            durationLabelBackground.autoPinEdge(.leading, to: .leading, of: durationLabel, withOffset: -24)
            durationLabelBackground.centerXAnchor.constraint(equalTo: contentView.trailingAnchor).isActive = true
            durationLabelBackground.centerYAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
        }

        durationLabel.isHidden = false
        durationLabelBackground.isHidden = false
        durationLabel.text = OWSFormat.localizedDurationString(from: duration)
        durationLabel.sizeToFit()
    }

    func configure(item: PhotoGridItem, isLoading: Bool) {
        self.item = item

        image = item.asyncThumbnail { [weak self] image in
            guard let self = self, let currentItem = self.item, currentItem === item else { return }
            self.image = image
        }

        setMedia(itemType: item.type)

        switch item.type {
        case .animated:
            setContentTypeBadge(image: UIImage(imageLiteralResourceName: "gif-rectangle"))
        case .photo, .video:
            setContentTypeBadge(image: nil)
        }

        if isLoading { startLoading() }
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        item = nil
        imageView.image = nil
        stopLoading()
    }

    private func startLoading() {
        loadingIndicator.startAnimating()
    }

    private func stopLoading() {
        loadingIndicator.stopAnimating()
    }
}

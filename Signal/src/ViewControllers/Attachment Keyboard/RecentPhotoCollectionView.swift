//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import PhotosUI
import SignalServiceKit
import SignalUI

protocol RecentPhotosDelegate: AnyObject {
    func didSelectRecentPhoto(asset: PHAsset, attachment: PreviewableAttachment)
}

class RecentPhotosCollectionView: UICollectionView {

    static let maxRecentPhotos = 96
    static let itemSpacing: CGFloat = 12

    weak var recentPhotosDelegate: RecentPhotosDelegate?

    var mediaLibraryAuthorizationStatus: PHAuthorizationStatus = .notDetermined {
        didSet {
            guard oldValue != mediaLibraryAuthorizationStatus else { return }
            DispatchQueue.main.async {
                self.reloadUIOnMediaLibraryAuthorizationStatusChange()
            }
        }
    }

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
        library.delegate = self
        return library
    }()
    private lazy var collection = photoLibrary.defaultPhotoAlbum()
    private lazy var collectionContents = collection.contents(limit: RecentPhotosCollectionView.maxRecentPhotos)

    // Cell Sizing

    private static let initialCellSize: CGSize = .square(50)

    private var cellSize: CGSize = initialCellSize {
        didSet {
            guard oldValue != cellSize else { return }

            thumbnailSize = cellSize * UIScreen.main.scale

            // Replacing the collection view layout is the only reliable way
            // to change cell size when `collectionView(_:layout:sizeForItemAt:)` is implemented.
            // That delegate method is necessary to allow custom size for "manage access" helper UI.
            setCollectionViewLayout(RecentPhotosCollectionView.collectionViewLayout(itemSize: cellSize), animated: false)
            reloadData() // Needed in order to reload photos with better quality on size change.
        }
    }

    private var lastKnownHeight: CGFloat = 0

    override var bounds: CGRect {
        didSet {
            let height = frame.height
            guard height != lastKnownHeight, height > 0 else { return }

            lastKnownHeight = height
            recalculateCellSize()
        }
    }

    private func recalculateCellSize() {
        guard lastKnownHeight > 0 else { return }

        if lastKnownHeight > 250 {
            cellSize = CGSize(square: 0.5 * (lastKnownHeight - RecentPhotosCollectionView.itemSpacing))
        // Otherwise, assume the recent photos take up the full height of the collection view.
        } else {
            cellSize = CGSize(square: lastKnownHeight)
        }
    }

    private var thumbnailSize = initialCellSize * UIScreen.main.scale

    private static func collectionViewLayout(itemSize: CGSize) -> UICollectionViewFlowLayout {
        let layout = RTLEnabledCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = itemSpacing
        layout.minimumInteritemSpacing = itemSpacing
        layout.itemSize = itemSize
        return layout
    }

    init() {
        let layout = RecentPhotosCollectionView.collectionViewLayout(itemSize: RecentPhotosCollectionView.initialCellSize)
        super.init(frame: .zero, collectionViewLayout: layout)

        dataSource = self
        delegate = self

        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        let horizontalInset = OWSTableViewController2.defaultHOuterMargin
        contentInset = UIEdgeInsets(top: 0, leading: horizontalInset, bottom: 0, trailing: horizontalInset)
        register(RecentPhotoCell.self, forCellWithReuseIdentifier: RecentPhotoCell.reuseIdentifier)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Presentation Animations

    func prepareForPresentation() {
        UIView.performWithoutAnimation {
            self.alpha = 0
        }
    }

    func performPresentationAnimation() {
        UIView.animate(withDuration: 0.3) {
            self.alpha = 1
        }
    }

    // Background view

    private var hasPhotos: Bool {
        guard hasAccessToPhotos else { return false }
        return collectionContents.assetCount > 0
    }

    private var hasAccessToPhotos: Bool {
        return [.authorized, .limited].contains(mediaLibraryAuthorizationStatus)
    }

    private func reloadUIOnMediaLibraryAuthorizationStatusChange() {
        guard hasPhotos else {
            backgroundView = noPhotosBackgroundView()
            reloadData()
            return
        }
        backgroundView = nil
        reloadData()
    }

    private func noPhotosBackgroundView() -> UIView {
        let contentView: UIView
        if !hasAccessToPhotos {
            contentView = noAccessToPhotosView()
        } else {
            contentView = noPhotosView()
        }

        let view = UIView()
        view.addSubview(contentView)
        contentView.autoPinHeightToSuperviewMargins(relation: .lessThanOrEqual)
        contentView.autoCenterInSuperview()
        contentView.widthAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.widthAnchor, multiplier: 0.75).isActive = true
        return view
    }

    private func noPhotosView() -> UIView {
        let titleLabel = UILabel()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = .dynamicTypeHeadlineClamped
        titleLabel.textColor = .Signal.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.text = OWSLocalizedString(
            "ATTACHMENT_KEYBOARD_NO_MEDIA_TITLE",
            comment: "First block of text in chat attachment panel when there's no recent photos to show."
        )
        let bodyLabel = textLabel(text: OWSLocalizedString(
            "ATTACHMENT_KEYBOARD_NO_MEDIA_BODY",
            comment: "Second block of text in chat attachment panel when there's no recent photos to show."
        ))
        let stackView = UIStackView(arrangedSubviews: [ titleLabel, bodyLabel ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 4
        return stackView
    }

    private func noAccessToPhotosView() -> UIView {
        let textLabel = textLabel(text: OWSLocalizedString(
            "ATTACHMENT_KEYBOARD_NO_PHOTO_ACCESS",
            comment: "Text in chat attachment panel explaining that user needs to give Signal permission to access photos."
        ))
        let button = UIButton(
            configuration: .smallSecondary(title: OWSLocalizedString(
                "ATTACHMENT_KEYBOARD_OPEN_SETTINGS",
                comment: "Button in chat attachment panel to let user open Settings app and give Signal persmission to access photos."
            )),
            primaryAction: UIAction { _ in
                let openAppSettingsUrl = URL(string: UIApplication.openSettingsURLString)!
                UIApplication.shared.open(openAppSettingsUrl)
            }
        )
        let stackView = UIStackView(arrangedSubviews: [ textLabel, button ])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        return stackView
    }

    private func textLabel(text: String) -> UILabel {
        let label = UILabel()
        label.adjustsFontForContentSizeCategory = true
        label.font = .dynamicTypeSubheadlineClamped
        label.lineBreakMode = .byWordWrapping
        label.textColor = .Signal.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = text
        return label
    }
}

extension RecentPhotosCollectionView: PhotoLibraryDelegate {

    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary) {
        let hadPhotos = hasPhotos
        collectionContents = collection.contents(limit: RecentPhotosCollectionView.maxRecentPhotos)
        reloadData()
        if hasPhotos != hadPhotos {
            reloadUIOnMediaLibraryAuthorizationStatusChange()
        }
    }
}

// MARK: - UICollectionViewDelegate

extension RecentPhotosCollectionView: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard fetchingAttachmentIndex == nil else { return }

        guard indexPath.row < collectionContents.assetCount else {
            owsFailDebug("Asset does not exist.")
            return
        }

        self.fetchingAttachmentIndex = indexPath
        let asset = collectionContents.asset(at: indexPath.item)
        Task {
            defer {
                self.fetchingAttachmentIndex = nil
            }
            do {
                let attachment = try await collectionContents.outgoingAttachment(for: asset)
                self.recentPhotosDelegate?.didSelectRecentPhoto(asset: asset, attachment: attachment)
            } catch {
                Logger.warn("\(error)")
                switch error {
                case SignalAttachmentError.fileSizeTooLarge:
                    OWSActionSheets.showActionSheet(
                        title: OWSLocalizedString(
                            "ATTACHMENT_ERROR_FILE_SIZE_TOO_LARGE",
                            comment: "Attachment error message for attachments whose data exceed file size limits"
                        )
                    )
                default:
                    OWSActionSheets.showActionSheet(
                        title: OWSLocalizedString(
                            "IMAGE_PICKER_FAILED_TO_PROCESS_ATTACHMENTS",
                            comment: "alert title",
                        ),
                    )
                }
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return cellSize
    }
}

// MARK: - UICollectionViewDataSource

extension RecentPhotosCollectionView: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        guard hasPhotos else { return 0 }
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        guard hasPhotos else { return 0 }
        return collectionContents.assetCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RecentPhotoCell.reuseIdentifier, for: indexPath) as? RecentPhotoCell else {
            owsFail("cell was unexpectedly nil")
        }

        let assetItem = collectionContents.assetItem(at: indexPath.item, thumbnailSize: thumbnailSize)
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

    private var item: PhotoPickerAssetItem?

    override init(frame: CGRect) {

        super.init(frame: frame)

        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        contentView.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges()

        loadingIndicator.layer.shadowColor = UIColor.black.cgColor
        loadingIndicator.layer.shadowOffset = .zero
        loadingIndicator.layer.shadowOpacity = 0.7
        loadingIndicator.layer.shadowRadius = 3.0

        contentView.addSubview(loadingIndicator)
        loadingIndicator.autoCenterInSuperview()

        if #available(iOS 26, *) {
            updateCornerRadius()
            registerForTraitChanges([ UITraitVerticalSizeClass.self ]) { (self: Self, _) in
                self.updateCornerRadius()
            }
        }
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var bounds: CGRect {
        didSet {
            guard #unavailable(iOS 26) else { return }
            updateCornerRadiusLegacy()
        }
    }

    @available(iOS 26, *)
    private func updateCornerRadius() {
        let cornerRadius: CGFloat = traitCollection.verticalSizeClass == .compact ? 20 : 36
        contentView.cornerConfiguration = .uniformCorners(radius: .fixed(cornerRadius))
    }

    @available(iOS, deprecated: 26)
    private func updateCornerRadiusLegacy() {
        let cellSize = min(bounds.width, bounds.height)
        guard cellSize > 0 else { return }
        contentView.layer.cornerRadius = (cellSize * 13 / 84).rounded()
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
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .footnote)
        return UIFont.semiboldFont(ofSize: max(13, fontDescriptor.pointSize))
    }

    private func setContentTypeBadge(image: UIImage?) {
        guard image != nil else {
            contentTypeBadgeView?.isHidden = true
            return
        }

        if contentTypeBadgeView == nil {
            let contentTypeBadgeView = UIImageView()
            contentView.addSubview(contentTypeBadgeView)
            contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 12)
            contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 12)
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
            durationLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 12)
            durationLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: 12)
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

    func configure(item: PhotoPickerAssetItem, isLoading: Bool) {
        self.item = item

        image = nil
        item.asyncThumbnail { [weak self] image in
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

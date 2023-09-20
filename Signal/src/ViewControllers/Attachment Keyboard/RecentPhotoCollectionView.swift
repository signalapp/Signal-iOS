//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import PhotosUI
import SignalMessaging
import SignalUI

protocol RecentPhotosDelegate: AnyObject {
    func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment)
}

class RecentPhotosCollectionView: UICollectionView {

    static let maxRecentPhotos = 96
    static let itemSpacing: CGFloat = 12

    weak var recentPhotosDelegate: RecentPhotosDelegate?

    var mediaLibraryAuthorizationStatus: PHAuthorizationStatus = .notDetermined {
        didSet {
            guard oldValue != mediaLibraryAuthorizationStatus else { return }
            reloadUIOnMediaLibraryAuthorizationStatusChange()
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
        library.add(delegate: self)
        return library
    }()
    private lazy var collection = photoLibrary.defaultPhotoAlbum()
    private lazy var collectionContents = collection.contents(ascending: false, limit: RecentPhotosCollectionView.maxRecentPhotos)

    // Cell Sizing

    private static let initialCellSize: CGSize = .square(50)

    private var cellSize: CGSize = initialCellSize {
        didSet {
            guard oldValue != cellSize else { return }
            // Replacing the collection view layout is the only reliable way
            // to change cell size when `collectionView(_:layout:sizeForItemAt:)` is implemented.
            // That delegate method is necessary to allow custom size for "manage access" helper UI.
            setCollectionViewLayout(RecentPhotosCollectionView.collectionViewLayout(itemSize: cellSize), animated: false)
            reloadData() // Needed in order to reload photos with better quality on size change.
        }
    }
    private var limitedAccessViewCellSizeCache: [CGFloat: CGSize] = [:]

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

    private var photoMediaSize: PhotoMediaSize {
        let size = PhotoMediaSize()
        size.thumbnailSize = cellSize
        return size
    }

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
        register(UICollectionViewCell.self, forCellWithReuseIdentifier: "SelectMorePhotosCell")
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
        guard #available(iOS 14, *) else {
            return mediaLibraryAuthorizationStatus == .authorized
        }
        return [.authorized, .limited].contains(mediaLibraryAuthorizationStatus)
    }

    private var isAccessToPhotosLimited: Bool {
        guard #available(iOS 14, *) else { return false }
        return mediaLibraryAuthorizationStatus == .limited
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
        } else if isAccessToPhotosLimited {
            contentView = limitedAccessView()
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
        let titleLabel = titleLabel(text: OWSLocalizedString(
            "ATTACHMENT_KEYBOARD_NO_MEDIA_TITLE",
            comment: "First block of text in chat attachment panel when there's no recent photos to show."
        ))
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

    private func limitedAccessView() -> UIView {
        let textLabel = textLabel(text: OWSLocalizedString(
            "ATTACHMENT_KEYBOARD_LIMITED_ACCESS",
            comment: "Text in chat attachment panel when Signal only has access to some photos/videos."
        ))
        let button = button(title: OWSLocalizedString(
            "ATTACHMENT_KEYBOARD_BUTTON_MANAGE",
            comment: "Button in chat attachment panel that allows to select photos/videos Signal has access to."
        ))
        button.block = {
            guard #available(iOS 14, *),
                let frontmostVC = CurrentAppContext().frontmostViewController() else { return }
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: frontmostVC)
        }
        let stackView = UIStackView(arrangedSubviews: [ textLabel, button ])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        return stackView
    }

    private func noAccessToPhotosView() -> UIView {
        let textLabel = textLabel(text: OWSLocalizedString(
            "ATTACHMENT_KEYBOARD_NO_PHOTO_ACCESS",
            comment: "Text in chat attachment panel explaining that user needs to give Signal permission to access photos."
        ))
        let button = button(title: OWSLocalizedString(
            "ATTACHMENT_KEYBOARD_OPEN_SETTINGS",
            comment: "Button in chat attachment panel to let user open Settings app and give Signal persmission to access photos."
        ))
        button.block = {
            let openAppSettingsUrl = URL(string: UIApplication.openSettingsURLString)!
            UIApplication.shared.open(openAppSettingsUrl)
        }
        let stackView = UIStackView(arrangedSubviews: [ textLabel, button ])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        return stackView
    }

    private func titleLabel(text: String) -> UILabel {
        let label = UILabel()
        label.font = .dynamicTypeHeadlineClamped
        label.textColor = Theme.isDarkThemeEnabled ? .ows_gray20 : UIColor(rgbHex: 0x434343).withAlphaComponent(0.8)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.text = text
        return label
    }

    private func textLabel(text: String) -> UILabel {
        let label = UILabel()
        label.font = .dynamicTypeSubheadlineClamped
        label.lineBreakMode = .byWordWrapping
        label.textColor = Theme.isDarkThemeEnabled ? .ows_gray25 : .ows_blackAlpha50
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = text
        return label
    }

    private func button(title: String) -> OWSButton {
        let button = OWSButton()

        let backgroundColor = Theme.isDarkThemeEnabled ? UIColor(white: 1, alpha: 0.16) : UIColor(white: 0, alpha: 0.08)
        button.setBackgroundImage(UIImage(color: backgroundColor), for: .normal)

        let highlightedBgColor = Theme.isDarkThemeEnabled ? UIColor(white: 1, alpha: 0.26) : UIColor(white: 0, alpha: 0.18)
        button.setBackgroundImage(UIImage(color: highlightedBgColor), for: .highlighted)

        button.contentEdgeInsets = UIEdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        button.layer.masksToBounds = true
        button.layer.cornerRadius = 16

        button.setTitle(title, for: .normal)
        button.setTitleColor(Theme.isDarkThemeEnabled ? .ows_gray05 : .black, for: .normal)
        button.titleLabel?.font = .dynamicTypeSubheadlineClamped.semibold()
        return button
    }
}

extension RecentPhotosCollectionView: PhotoLibraryDelegate {

    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary) {
        let hadPhotos = hasPhotos
        collectionContents = collection.contents(ascending: false, limit: RecentPhotosCollectionView.maxRecentPhotos)
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

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {

        // Custom size for "manage access" cell.
        guard indexPath.row < collectionContents.assetCount else {
            let defaultCellSize = cellSize
            guard defaultCellSize.isNonEmpty else { return .zero }

            let cellHeight = defaultCellSize.height
            if let cachedSize = limitedAccessViewCellSizeCache[cellHeight] {
                return cachedSize
            }

            let cellMargin: CGFloat = 8
            let view = limitedAccessView()

            // I couldn't figure out how to make `systemLayoutSizeFitting()` work for multi-line text.
            // Size (width) that method returns is always for text being one line.
            // Therefore the logic is as follows:
            // 1. Check if UI fits standard cell width.
            // 2a. If it does - all good and we use default cell size.
            // 2b. If it doesn't - we calculate size (width) with default cell size being restricted.
            //     Unfortunately in this case width is always for one line of text like I mentioned above.
            // If you read this and have some free time - feel free to attempt to fix.
            let size = view.systemLayoutSizeFitting(
                CGSize(width: defaultCellSize.width - 2*cellMargin, height: .greatestFiniteMagnitude),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            let cellWidth: CGFloat
            if size.height > cellHeight {
                view.addConstraint(view.heightAnchor.constraint(equalToConstant: cellHeight))

                let widerSize = view.systemLayoutSizeFitting(.square(.greatestFiniteMagnitude))
                cellWidth = widerSize.width + 2*cellMargin
            } else {
                cellWidth = defaultCellSize.width
            }
            let cellSize = CGSize(width: cellWidth, height: cellHeight)
            limitedAccessViewCellSizeCache[cellHeight] = cellSize
            return cellSize
        }

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

        var cellCount = collectionContents.assetCount
        if isAccessToPhotosLimited {
            cellCount += 1
        }
        return cellCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard indexPath.row < collectionContents.assetCount else {
            // If the index is beyond the asset count, we should be rendering the "select more photos" prompt.
            owsAssertDebug(isAccessToPhotosLimited)

            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "SelectMorePhotosCell", for: indexPath)
            if cell.contentView.subviews.isEmpty {
                let limitedAccessView = limitedAccessView()
                cell.contentView.addSubview(limitedAccessView)
                limitedAccessView.autoVCenterInSuperview()
                limitedAccessView.autoPinHeightToSuperview(relation: .lessThanOrEqual)
                limitedAccessView.autoPinWidthToSuperviewMargins()
            }
            return cell
        }

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

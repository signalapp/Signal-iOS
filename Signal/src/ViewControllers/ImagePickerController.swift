//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import Photos
import PromiseKit

@objc(OWSImagePickerControllerDelegate)
protocol ImagePickerControllerDelegate {
    func imagePicker(_ imagePicker: ImagePickerGridController, didPickImageAttachments attachments: [SignalAttachment])
}

@objc(OWSImagePickerGridController)
class ImagePickerGridController: UICollectionViewController, PhotoLibraryDelegate {

    @objc
    weak var delegate: ImagePickerControllerDelegate?

    private let library: PhotoLibrary = PhotoLibrary()
    private let libraryAlbum: PhotoLibraryAlbum

    var availableWidth: CGFloat = 0

    var collectionViewFlowLayout: UICollectionViewFlowLayout

    init() {
        collectionViewFlowLayout = type(of: self).buildLayout()
        libraryAlbum = library.albumForAllPhotos()
        super.init(collectionViewLayout: collectionViewFlowLayout)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = libraryAlbum.localizedTitle

        library.delegate = self

        guard let collectionView = collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        collectionView.register(PhotoGridViewCell.self, forCellWithReuseIdentifier: PhotoGridViewCell.reuseIdentifier)

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                           target: self,
                                                           action: #selector(didPressCancel))
        let featureFlag_isMultiselectEnabled = true
        if featureFlag_isMultiselectEnabled {
            updateSelectButton()
        }

        collectionView.backgroundColor = Theme.backgroundColor
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Determine the size of the thumbnails to request
        let scale = UIScreen.main.scale
        let cellSize = collectionViewFlowLayout.itemSize
        libraryAlbum.thumbnailSize = CGSize(width: cellSize.width * scale, height: cellSize.height * scale)
    }

    // MARK: Actions

    @objc
    func didPressCancel(sender: UIBarButtonItem) {
        self.dismiss(animated: true)
    }

    // MARK: Layout

    static let kInterItemSpacing: CGFloat = 2
    private class func buildLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()

        if #available(iOS 11, *) {
            layout.sectionInsetReference = .fromSafeArea
        }
        layout.minimumInteritemSpacing = kInterItemSpacing
        layout.minimumLineSpacing = kInterItemSpacing
        layout.sectionHeadersPinToVisibleBounds = true

        return layout
    }

    func updateLayout() {
        let containerWidth: CGFloat
        if #available(iOS 11.0, *) {
            containerWidth = self.view.safeAreaLayoutGuide.layoutFrame.size.width
        } else {
            containerWidth = self.view.frame.size.width
        }

        let kItemsPerPortraitRow = 4
        let screenWidth = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let approxItemWidth = screenWidth / CGFloat(kItemsPerPortraitRow)

        let itemCount = round(containerWidth / approxItemWidth)
        let spaceWidth = (itemCount + 1) * type(of: self).kInterItemSpacing
        let availableWidth = containerWidth - spaceWidth

        let itemWidth = floor(availableWidth / CGFloat(itemCount))
        let newItemSize = CGSize(width: itemWidth, height: itemWidth)

        if (newItemSize != collectionViewFlowLayout.itemSize) {
            collectionViewFlowLayout.itemSize = newItemSize
            collectionViewFlowLayout.invalidateLayout()
        }
    }

    // MARK: Batch Selection

    lazy var doneButton: UIBarButtonItem = {
        return UIBarButtonItem(barButtonSystemItem: .done,
                               target: self,
                               action: #selector(didPressDone))
    }()

    lazy var selectButton: UIBarButtonItem = {
        return UIBarButtonItem(title: NSLocalizedString("BUTTON_SELECT", comment: "Button text to enable batch selection mode"),
                               style: .plain,
                               target: self,
                               action: #selector(didTapSelect))
    }()

    var isInBatchSelectMode = false {
        didSet {
            collectionView!.allowsMultipleSelection = isInBatchSelectMode
            updateSelectButton()
            updateDoneButton()
        }
    }

    @objc
    func didPressDone(_ sender: Any) {
        Logger.debug("")

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        guard let indexPaths = collectionView.indexPathsForSelectedItems else {
            owsFailDebug("indexPaths was unexpectedly nil")
            return
        }

        let assets: [PHAsset] = indexPaths.compactMap { return self.libraryAlbum.asset(at: $0.row) }
        let promises = assets.map { return libraryAlbum.outgoingAttachment(for: $0) }
        when(fulfilled: promises).map { attachments in
            self.dismiss(animated: true) {
                self.delegate?.imagePicker(self, didPickImageAttachments: attachments)
            }
        }.retainUntilComplete()
    }

    func updateDoneButton() {
        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        if let count = collectionView.indexPathsForSelectedItems?.count, count > 0 {
            self.doneButton.isEnabled = true
        } else {
            self.doneButton.isEnabled = false
        }
    }

    func updateSelectButton() {
        navigationItem.rightBarButtonItem = isInBatchSelectMode ? doneButton : selectButton
    }

    @objc
    func didTapSelect(_ sender: Any) {
        isInBatchSelectMode = true

        // disabled until at least one item is selected
        self.doneButton.isEnabled = false
    }

    @objc
    func didCancelSelect(_ sender: Any) {
        endSelectMode()
    }

    func endSelectMode() {
        isInBatchSelectMode = false

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        // deselect any selected
        collectionView.indexPathsForSelectedItems?.forEach { collectionView.deselectItem(at: $0, animated: false)}
    }

    // MARK: PhotoLibraryDelegate

    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary) {
        collectionView?.reloadData()
    }

    // MARK: UICollectionView

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isInBatchSelectMode {
            updateDoneButton()
        } else {
            let asset = libraryAlbum.asset(at: indexPath.row)
            firstly {
                libraryAlbum.outgoingAttachment(for: asset)
            }.map { attachment in
                self.dismiss(animated: true) {
                    self.delegate?.imagePicker(self, didPickImageAttachments: [attachment])
                }
            }.retainUntilComplete()
        }
    }

    public override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        Logger.debug("")

        if isInBatchSelectMode {
            updateDoneButton()
        }
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return libraryAlbum.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoGridViewCell.reuseIdentifier, for: indexPath) as? PhotoGridViewCell else {
            owsFail("cell was unexpectedly nil")
        }

        let mediaItem = libraryAlbum.mediaItem(at: indexPath.item)
        cell.configure(item: mediaItem)
        return cell
    }

}

protocol PhotoLibraryDelegate: class {
    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary)
}

class ImagePickerGridItem: PhotoGridItem {

    let asset: PHAsset
    let album: PhotoLibraryAlbum

    init(asset: PHAsset, album: PhotoLibraryAlbum) {
        self.asset = asset
        self.album = album
    }

    // MARK: PhotoGridItem

    var type: PhotoGridItemType {
        if asset.mediaType == .video {
            return .video
        }

        // TODO show GIF badge?

        return  .photo
    }

    func asyncThumbnail(completion: @escaping (UIImage?) -> Void) -> UIImage? {
        album.requestThumbnail(for: self.asset) { image, _ in
            completion(image)
        }
        return nil
    }
}

class PhotoLibraryAlbum {

    let fetchResult: PHFetchResult<PHAsset>
    let localizedTitle: String?
    var thumbnailSize: CGSize = .zero

    enum PhotoLibraryError: Error {
        case assertionError(_ description: String)
        case unsupportedMediaType

    }

    init(fetchResult: PHFetchResult<PHAsset>, localizedTitle: String?) {
        self.fetchResult = fetchResult
        self.localizedTitle = localizedTitle
    }

    var count: Int {
        return fetchResult.count
    }

    private let imageManager = PHCachingImageManager()

    func asset(at index: Int) -> PHAsset {
        return fetchResult.object(at: index)
    }

    func mediaItem(at index: Int) -> ImagePickerGridItem {
        let mediaAsset = asset(at: index)
        return ImagePickerGridItem(asset: mediaAsset, album: self)
    }

    // MARK: ImageManager

    func requestThumbnail(for asset: PHAsset, resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) {
        _ = imageManager.requestImage(for: asset, targetSize: thumbnailSize, contentMode: .aspectFill, options: nil, resultHandler: resultHandler)
    }

    private func requestImageDataSource(for asset: PHAsset) -> Promise<(dataSource: DataSource, dataUTI: String)> {
        return Promise { resolver in
            _ = imageManager.requestImageData(for: asset, options: nil) { imageData, dataUTI, orientation, info in
                guard let imageData = imageData else {
                    resolver.reject(PhotoLibraryError.assertionError("imageData was unexpectedly nil"))
                    return
                }

                guard let dataUTI = dataUTI else {
                    resolver.reject(PhotoLibraryError.assertionError("dataUTI was unexpectedly nil"))
                    return
                }

                guard let dataSource = DataSourceValue.dataSource(with: imageData, utiType: dataUTI) else {
                    resolver.reject(PhotoLibraryError.assertionError("dataSource was unexpectedly nil"))
                    return
                }

                resolver.fulfill((dataSource: dataSource, dataUTI: dataUTI))
            }
        }
    }

    private func requestVideoDataSource(for asset: PHAsset) -> Promise<(dataSource: DataSource, dataUTI: String)> {
        return Promise { resolver in

            _ = imageManager.requestExportSession(forVideo: asset, options: nil, exportPreset: AVAssetExportPresetMediumQuality) { exportSession, info in

                guard let exportSession = exportSession else {
                    resolver.reject(PhotoLibraryError.assertionError("exportSession was unexpectedly nil"))
                    return
                }

                exportSession.outputFileType = AVFileType.mp4
                exportSession.metadataItemFilter = AVMetadataItemFilter.forSharing()

                let exportPath = OWSFileSystem.temporaryFilePath(withFileExtension: "mp4")
                let exportURL = URL(fileURLWithPath: exportPath)
                exportSession.outputURL = exportURL

                Logger.debug("starting video export")
                exportSession.exportAsynchronously {
                    Logger.debug("Completed video export")

                    guard let dataSource = DataSourcePath.dataSource(with: exportURL, shouldDeleteOnDeallocation: true) else {
                        resolver.reject(PhotoLibraryError.assertionError("Failed to build data source for exported video URL"))
                        return
                    }

                    resolver.fulfill((dataSource: dataSource, dataUTI: kUTTypeMPEG4 as String))
                }
            }
        }
    }

    func outgoingAttachment(for asset: PHAsset) -> Promise<SignalAttachment> {
        switch asset.mediaType {
        case .image:
            return requestImageDataSource(for: asset).map { (dataSource: DataSource, dataUTI: String) in
                return SignalAttachment.attachment(dataSource: dataSource, dataUTI: dataUTI, imageQuality: .medium)
            }
        case .video:
            return requestVideoDataSource(for: asset).map { (dataSource: DataSource, dataUTI: String) in
                return SignalAttachment.attachment(dataSource: dataSource, dataUTI: dataUTI)
            }
        default:
            return Promise(error: PhotoLibraryError.unsupportedMediaType)
        }
    }
}

class PhotoLibrary: NSObject, PHPhotoLibraryChangeObserver {
    weak var delegate: PhotoLibraryDelegate?

    var assetCollection: PHAssetCollection!
    var availableWidth: CGFloat = 0

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async {
            self.delegate?.photoLibraryDidChange(self)
        }
    }

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func albumForAllPhotos() -> PhotoLibraryAlbum {
        let allPhotosOptions = PHFetchOptions()
        allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let fetchResult = PHAsset.fetchAssets(with: allPhotosOptions)

        let title = NSLocalizedString("PHOTO_PICKER_DEFAULT_ALBUM", comment: "navbar title when viewing the default photo album, which includes all photos")
        return PhotoLibraryAlbum(fetchResult: fetchResult, localizedTitle: title)
    }
}

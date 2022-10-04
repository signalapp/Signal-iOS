//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import Photos
import PromiseKit
import CoreServices

protocol PhotoLibraryDelegate: AnyObject {
    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary)
}

class PhotoMediaSize {
    var thumbnailSize: CGSize

    init() {
        self.thumbnailSize = .zero
    }

    init(thumbnailSize: CGSize) {
        self.thumbnailSize = thumbnailSize
    }
}

class PhotoPickerAssetItem: PhotoGridItem {

    let asset: PHAsset
    let photoCollectionContents: PhotoCollectionContents
    let photoMediaSize: PhotoMediaSize

    init(asset: PHAsset, photoCollectionContents: PhotoCollectionContents, photoMediaSize: PhotoMediaSize) {
        self.asset = asset
        self.photoCollectionContents = photoCollectionContents
        self.photoMediaSize = photoMediaSize
    }

    // MARK: PhotoGridItem

    var type: PhotoGridItemType {
        if asset.mediaType == .video {
            return .video
        }

        // TODO show GIF badge?

        return  .photo
    }

    func asyncThumbnail(completion: @escaping (UIImage?) -> Void) {
        var hasLoadedImage = false

        // Surprisingly, iOS will opportunistically run the completion block sync if the image is
        // already available.
        photoCollectionContents.requestThumbnail(for: self.asset, thumbnailSize: photoMediaSize.thumbnailSize) { image, _ in
            DispatchMainThreadSafe({
                // Once we've _successfully_ completed (e.g. invoked the completion with
                // a non-nil image), don't invoke the completion again with a nil argument.
                if !hasLoadedImage || image != nil {
                    completion(image)

                    if image != nil {
                        hasLoadedImage = true
                    }
                }
            })
        }
    }
}

class PhotoCollectionContents {

    let fetchResult: PHFetchResult<PHAsset>
    let localizedTitle: String?

    enum PhotoLibraryError: Error {
        case assertionError(description: String)
        case unsupportedMediaType
    }

    init(fetchResult: PHFetchResult<PHAsset>, localizedTitle: String?) {
        self.fetchResult = fetchResult
        self.localizedTitle = localizedTitle
    }

    private let imageManager = PHCachingImageManager()

    // MARK: - Asset Accessors

    var assetCount: Int {
        return fetchResult.count
    }

    var lastAsset: PHAsset? {
        guard assetCount > 0 else {
            return nil
        }
        return asset(at: assetCount - 1)
    }

    var firstAsset: PHAsset? {
        guard assetCount > 0 else {
            return nil
        }
        return asset(at: 0)
    }

    func asset(at index: Int) -> PHAsset {
        return fetchResult.object(at: index)
    }

    // MARK: - AssetItem Accessors

    func assetItem(at index: Int, photoMediaSize: PhotoMediaSize) -> PhotoPickerAssetItem {
        let mediaAsset = asset(at: index)
        return PhotoPickerAssetItem(asset: mediaAsset, photoCollectionContents: self, photoMediaSize: photoMediaSize)
    }

    func firstAssetItem(photoMediaSize: PhotoMediaSize) -> PhotoPickerAssetItem? {
        guard let mediaAsset = firstAsset else {
            return nil
        }
        return PhotoPickerAssetItem(asset: mediaAsset, photoCollectionContents: self, photoMediaSize: photoMediaSize)
    }

    func lastAssetItem(photoMediaSize: PhotoMediaSize) -> PhotoPickerAssetItem? {
        guard let mediaAsset = lastAsset else {
            return nil
        }
        return PhotoPickerAssetItem(asset: mediaAsset, photoCollectionContents: self, photoMediaSize: photoMediaSize)
    }

    // MARK: ImageManager

    func requestThumbnail(for asset: PHAsset, thumbnailSize: CGSize, resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) {
        _ = imageManager.requestImage(for: asset, targetSize: thumbnailSize, contentMode: .aspectFill, options: nil, resultHandler: resultHandler)
    }

    private func requestImageDataSource(for asset: PHAsset) -> Promise<(dataSource: DataSource, dataUTI: String)> {
        return Promise { resolver in

            let options: PHImageRequestOptions = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true

            _ = imageManager.requestImageData(for: asset, options: options) { imageData, dataUTI, orientation, info in

                guard let imageData = imageData else {
                    resolver.reject(PhotoLibraryError.assertionError(description: "imageData was unexpectedly nil"))
                    return
                }

                guard let dataUTI = dataUTI else {
                    resolver.reject(PhotoLibraryError.assertionError(description: "dataUTI was unexpectedly nil"))
                    return
                }

                guard let dataSource = DataSourceValue.dataSource(with: imageData, utiType: dataUTI) else {
                    resolver.reject(PhotoLibraryError.assertionError(description: "dataSource was unexpectedly nil"))
                    return
                }

                resolver.fulfill((dataSource: dataSource, dataUTI: dataUTI))
            }
        }
    }

    private func requestVideoDataSource(for asset: PHAsset) -> Promise<(dataSource: DataSource, dataUTI: String)> {
        return Promise { resolver in

            let options: PHVideoRequestOptions = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true

            _ = imageManager.requestExportSession(forVideo: asset, options: options, exportPreset: AVAssetExportPresetMediumQuality) { exportSession, foo in

                guard let exportSession = exportSession else {
                    resolver.reject(PhotoLibraryError.assertionError(description: "exportSession was unexpectedly nil"))
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
                        resolver.reject(PhotoLibraryError.assertionError(description: "Failed to build data source for exported video URL"))
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

class PhotoCollection {
    public let id: String
    private let collection: PHAssetCollection
    
    // The user never sees this collection, but we use it for a null object pattern
    // when the user has denied photos access.
    static let empty = PhotoCollection(id: "", collection: PHAssetCollection())

    init(id: String, collection: PHAssetCollection) {
        self.id = id
        self.collection = collection
    }

    func localizedTitle() -> String {
        guard let localizedTitle = collection.localizedTitle?.stripped,
            localizedTitle.count > 0 else {
            return NSLocalizedString("PHOTO_PICKER_UNNAMED_COLLECTION", comment: "label for system photo collections which have no name.")
        }
        return localizedTitle
    }

    func contents() -> PhotoCollectionContents {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let fetchResult = PHAsset.fetchAssets(in: collection, options: options)

        return PhotoCollectionContents(fetchResult: fetchResult, localizedTitle: localizedTitle())
    }
}

extension PhotoCollection: Equatable {
    static func == (lhs: PhotoCollection, rhs: PhotoCollection) -> Bool {
        return lhs.collection == rhs.collection
    }
}

class PhotoLibrary: NSObject, PHPhotoLibraryChangeObserver {
    typealias WeakDelegate = Weak<PhotoLibraryDelegate>
    var delegates = [WeakDelegate]()

    public func add(delegate: PhotoLibraryDelegate) {
        delegates.append(WeakDelegate(value: delegate))
    }

    var assetCollection: PHAssetCollection!

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async {
            for weakDelegate in self.delegates {
                weakDelegate.value?.photoLibraryDidChange(self)
            }
        }
    }

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    private lazy var fetchOptions: PHFetchOptions = {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "endDate", ascending: true)]
        return fetchOptions
    }()

    func defaultPhotoCollection() -> PhotoCollection {
        var fetchedCollection: PhotoCollection?
        PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumUserLibrary,
            options: fetchOptions
        ).enumerateObjects { collection, _, stop in
            fetchedCollection = PhotoCollection(id: collection.localIdentifier, collection: collection)
            stop.pointee = true
        }

        guard let photoCollection = fetchedCollection else {
            Logger.info("Using empty photo collection.")
            assert(PHPhotoLibrary.authorizationStatus() == .denied)
            return PhotoCollection.empty
        }

        return photoCollection
    }

    func allPhotoCollections() -> [PhotoCollection] {
        var collections = [PhotoCollection]()
        var collectionIds = Set<String>()

        let processPHCollection: ((collection: PHCollection, hideIfEmpty: Bool)) -> Void = { arg in
            let (collection, hideIfEmpty) = arg

            // De-duplicate by id.
            let collectionId: String = collection.localIdentifier
            
            guard !collectionIds.contains(collectionId) else { return }
            collectionIds.insert(collectionId)

            guard let assetCollection = collection as? PHAssetCollection else {
                owsFailDebug("Asset collection has unexpected type: \(type(of: collection))")
                return
            }
            let photoCollection = PhotoCollection(id: collectionId, collection: assetCollection)
            guard !hideIfEmpty || photoCollection.contents().assetCount > 0 else {
                return
            }

            collections.append(photoCollection)
        }
        let processPHAssetCollections: ((fetchResult: PHFetchResult<PHAssetCollection>, hideIfEmpty: Bool)) -> Void = { arg in
            let (fetchResult, hideIfEmpty) = arg

            fetchResult.enumerateObjects { (assetCollection, _, _) in
                // We're already sorting albums by last-updated. "Recently Added" is mostly redundant
                guard assetCollection.assetCollectionSubtype != .smartAlbumRecentlyAdded else {
                    return
                }

                // undocumented constant
                let kRecentlyDeletedAlbumSubtype = PHAssetCollectionSubtype(rawValue: 1000000201)
                guard assetCollection.assetCollectionSubtype != kRecentlyDeletedAlbumSubtype else {
                    return
                }

                processPHCollection((collection: assetCollection, hideIfEmpty: hideIfEmpty))
            }
        }
        let processPHCollections: ((fetchResult: PHFetchResult<PHCollection>, hideIfEmpty: Bool)) -> Void = { arg in
            let (fetchResult, hideIfEmpty) = arg

            for index in 0..<fetchResult.count {
                processPHCollection((collection: fetchResult.object(at: index), hideIfEmpty: hideIfEmpty))
            }
        }
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "endDate", ascending: true)]

        // Try to add "Camera Roll" first.
        processPHAssetCollections((fetchResult: PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: fetchOptions),
                                   hideIfEmpty: false))

        // Favorites
        processPHAssetCollections((fetchResult: PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: fetchOptions),
                                   hideIfEmpty: true))

        // Smart albums.
        processPHAssetCollections((fetchResult: PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .albumRegular, options: fetchOptions),
                                   hideIfEmpty: true))

        // User-created albums.
        processPHCollections((fetchResult: PHAssetCollection.fetchTopLevelUserCollections(with: fetchOptions),
                              hideIfEmpty: true))

        return collections
    }
}

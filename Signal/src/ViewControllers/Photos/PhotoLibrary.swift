//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreServices
import Foundation
import Photos
import SignalServiceKit
import SignalUI

protocol PhotoLibraryDelegate: AnyObject {
    func photoLibraryDidChange(_ photoLibrary: PhotoLibrary)
}

class PhotoPickerAssetItem {
    private let asset: PHAsset
    private let photoCollectionContents: PhotoAlbumContents
    private let thumbnailSize: CGSize

    let type: PhotoGridItemType

    init(asset: PHAsset, photoCollectionContents: PhotoAlbumContents, thumbnailSize: CGSize) {
        self.asset = asset
        self.photoCollectionContents = photoCollectionContents
        self.thumbnailSize = thumbnailSize

        self.type = if asset.mediaType == .video {
            .video(Promise.value(asset.duration))
        } else if asset.playbackStyle == .imageAnimated {
            .animated
        } else {
            .photo
        }
    }

    func asyncThumbnail(completion: @escaping (UIImage?) -> Void) {
        var hasLoadedImage = false

        // Surprisingly, iOS will opportunistically run the completion block sync if the image is
        // already available.
        photoCollectionContents.requestThumbnail(for: self.asset, thumbnailSize: self.thumbnailSize) { image, _ in
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

class PhotoAlbumContents {

    private let fetchResult: PHFetchResult<PHAsset>
    private let limit: Int

    enum PhotoLibraryError: Error {
        case assertionError(description: String)
        case unsupportedMediaType
        case failedToExportAsset(underlyingError: Error?)
    }

    init(fetchResult: PHFetchResult<PHAsset>, limit: Int) {
        self.fetchResult = fetchResult
        self.limit = limit
    }

    private let imageManager = PHCachingImageManager()

    // MARK: - Asset Accessors

    var assetCount: Int {
        return min(fetchResult.count, limit)
    }

    func asset(at index: Int) -> PHAsset {
        return fetchResult.object(at: fetchResult.count - index - 1)
    }

    // MARK: - AssetItem Accessors

    func assetItem(at index: Int, thumbnailSize: CGSize) -> PhotoPickerAssetItem {
        let mediaAsset = asset(at: index)
        return PhotoPickerAssetItem(asset: mediaAsset, photoCollectionContents: self, thumbnailSize: thumbnailSize)
    }

    // MARK: ImageManager

    func requestThumbnail(for asset: PHAsset, thumbnailSize: CGSize, resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) {
        _ = imageManager.requestImage(for: asset, targetSize: thumbnailSize, contentMode: .aspectFill, options: nil, resultHandler: resultHandler)
    }

    private func requestImageDataSource(for asset: PHAsset) async throws -> (dataSource: DataSourcePath, dataUTI: String) {
        let options: PHImageRequestOptions = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        options.deliveryMode = .highQualityFormat
        let (imageData, dataUTI) = await withCheckedContinuation { continuation in
            _ = imageManager.requestImageDataAndOrientation(for: asset, options: options) { imageData, dataUTI, _, _ in
                continuation.resume(returning: (imageData, dataUTI))
            }
        }
        guard let imageData else {
            throw PhotoLibraryError.assertionError(description: "imageData was unexpectedly nil")
        }
        guard let dataUTI else {
            throw PhotoLibraryError.assertionError(description: "dataUTI was unexpectedly nil")
        }
        guard let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI) else {
            throw PhotoLibraryError.assertionError(description: "fileExtension was unexpectedly nil")
        }
        let dataSource = try DataSourcePath(writingTempFileData: imageData, fileExtension: fileExtension)
        return (dataSource: dataSource, dataUTI: dataUTI)
    }

    private func requestVideoDataSource(for asset: PHAsset) async throws -> AVAsset {
        let options: PHVideoRequestOptions = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current

        return try await withCheckedThrowingContinuation { continuation in
            _ = imageManager.requestAVAsset(forVideo: asset, options: options) { video, _, info in
                guard let video else {
                    let error = info?[PHImageErrorKey] as! Error?
                    continuation.resume(throwing: PhotoLibraryError.failedToExportAsset(underlyingError: error))
                    return
                }
                continuation.resume(returning: video)
            }
        }
    }

    func outgoingAttachment(for asset: PHAsset) async throws -> PreviewableAttachment {
        switch asset.mediaType {
        case .image:
            let (dataSource, dataUTI) = try await requestImageDataSource(for: asset)
            return try PreviewableAttachment.imageAttachment(dataSource: dataSource, dataUTI: dataUTI)
        case .video:
            let video = try await requestVideoDataSource(for: asset)
            return try await PreviewableAttachment.compressVideoAsMp4(asset: video, baseFilename: nil)
        case .unknown, .audio:
            fallthrough
        @unknown default:
            throw PhotoLibraryError.unsupportedMediaType
        }
    }
}

class PhotoAlbum {
    private let collection: PHAssetCollection

    /// The user never sees this collection, but we use it for a
    /// null object pattern when the user has denied photos access.
    static let empty = PhotoAlbum(collection: PHAssetCollection())

    init(collection: PHAssetCollection) {
        self.collection = collection
    }

    func contents(limit: Int) -> PhotoAlbumContents {
        let fetchResult = PHAsset.fetchAssets(in: collection, options: nil)
        return PhotoAlbumContents(fetchResult: fetchResult, limit: limit)
    }
}

class PhotoLibrary: NSObject, PHPhotoLibraryChangeObserver {
    weak var delegate: PhotoLibraryDelegate?

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

    func defaultPhotoAlbum() -> PhotoAlbum {
        var fetchedCollection: PhotoAlbum?
        PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumUserLibrary,
            options: fetchOptions,
        ).enumerateObjects { collection, _, stop in
            fetchedCollection = PhotoAlbum(collection: collection)
            stop.pointee = true
        }

        guard let photoCollection = fetchedCollection else {
            Logger.info("Using empty photo collection.")
            assert(PHPhotoLibrary.authorizationStatus() == .denied)
            return PhotoAlbum.empty
        }

        return photoCollection
    }

    private lazy var fetchOptions: PHFetchOptions = {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "endDate", ascending: true)]
        return fetchOptions
    }()
}

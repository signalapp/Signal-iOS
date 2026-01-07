//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class WallpaperImageStoreImpl: WallpaperImageStore {

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let attachmentValidator: AttachmentContentValidator
    private let db: any DB

    public init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        attachmentValidator: AttachmentContentValidator,
        db: any DB,
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.attachmentValidator = attachmentValidator
        self.db = db
    }

    public func setWallpaperImage(
        _ photo: UIImage?,
        for thread: TSThread,
        onInsert: @escaping (DBWriteTransaction) throws -> Void,
    ) async throws {
        guard let rowId = thread.sqliteRowId else {
            throw OWSAssertionError("Inserting wallpaper for uninserted thread!")
        }
        if let photo {
            let dataSource = try await dataSource(wallpaperImage: photo)
            try await setWallpaperImage(
                dataSource,
                owner: .threadWallpaperImage(threadRowId: rowId),
                onInsert: onInsert,
            )
        } else {
            try await setWallpaperImage(
                nil,
                owner: .threadWallpaperImage(threadRowId: rowId),
                onInsert: onInsert,
            )
        }
    }

    public func setGlobalThreadWallpaperImage(
        _ photo: UIImage?,
        onInsert: @escaping (DBWriteTransaction) throws -> Void,
    ) async throws {
        if let photo {
            let dataSource = try await dataSource(wallpaperImage: photo)
            try await setWallpaperImage(dataSource, owner: .globalThreadWallpaperImage, onInsert: onInsert)
        } else {
            try await setWallpaperImage(nil, owner: .globalThreadWallpaperImage, onInsert: onInsert)
        }
    }

    public func loadWallpaperImage(for thread: TSThread, tx: DBReadTransaction) -> UIImage? {
        guard let rowId = thread.sqliteRowId else {
            owsFailDebug("Fetching wallpaper for uninserted thread!")
            return nil
        }
        return loadWallpaperImage(ownerId: .threadWallpaperImage(threadRowId: rowId), tx: tx)
    }

    public func loadGlobalThreadWallpaper(tx: DBReadTransaction) -> UIImage? {
        return loadWallpaperImage(ownerId: .globalThreadWallpaperImage, tx: tx)
    }

    public func copyWallpaperImage(from fromThread: TSThread, to toThread: TSThread, tx: DBWriteTransaction) throws {
        guard let fromRowId = fromThread.sqliteRowId, let toRowId = toThread.sqliteRowId else {
            throw OWSAssertionError("Copying wallpaper for uninserted threads!")
        }
        guard let fromReference = attachmentStore.fetchAnyReference(owner: .threadWallpaperImage(threadRowId: fromRowId), tx: tx) else {
            // Nothing to copy.
            return
        }

        // If the toThread had a wallpaper, remove it.
        if let toReference = attachmentStore.fetchAnyReference(owner: .threadWallpaperImage(threadRowId: toRowId), tx: tx) {
            try attachmentStore.removeOwner(reference: toReference, tx: tx)
        }

        switch fromReference.owner {
        case .thread(let threadSource):
            try attachmentStore.duplicateExistingThreadOwner(
                threadSource,
                with: fromReference,
                newOwnerThreadRowId: toRowId,
                tx: tx,
            )
        default:
            throw OWSAssertionError("Unexpected attachment reference type")
        }
    }

    public func resetAllWallpaperImages(tx: DBWriteTransaction) throws {
        try attachmentStore.removeAllThreadOwners(tx: tx)
    }

    // MARK: - Private

    private func dataSource(wallpaperImage photo: UIImage) async throws -> AttachmentDataSource {
        let mimeType = MimeType.imageJpeg.rawValue
        guard
            let imageData = photo.jpegData(compressionQuality: 0.8)
        else {
            throw OWSAssertionError("Failed to get jpg data for wallpaper photo")
        }
        let pendingAttachment = try await attachmentValidator.validateDataContents(
            imageData,
            mimeType: mimeType,
            renderingFlag: .default,
            sourceFilename: nil,
        )
        return .pendingAttachment(pendingAttachment)
    }

    private func setWallpaperImage(
        _ dataSource: AttachmentDataSource?,
        owner: AttachmentReference.OwnerBuilder,
        onInsert: @escaping (DBWriteTransaction) throws -> Void,
    ) async throws {
        try await db.awaitableWrite { tx in
            // First remove any existing wallpaper.
            if let existingReference = self.attachmentStore.fetchAnyReference(owner: owner.id, tx: tx) {
                try self.attachmentStore.removeOwner(reference: existingReference, tx: tx)
            }
            // Set the new image if any.
            if let dataSource {
                let dataSource = OwnedAttachmentDataSource(
                    dataSource: dataSource,
                    owner: owner,
                )
                try self.attachmentManager.createAttachmentStream(from: dataSource, tx: tx)
            }
            try onInsert(tx)
        }
    }

    private func loadWallpaperImage(ownerId: AttachmentReference.OwnerId, tx: DBReadTransaction) -> UIImage? {
        guard
            let attachment = attachmentStore.fetchAnyReferencedAttachment(
                for: ownerId,
                tx: tx,
            )
        else {
            return nil
        }
        return try? attachment.attachment.asStream()?.decryptedImage()
    }
}

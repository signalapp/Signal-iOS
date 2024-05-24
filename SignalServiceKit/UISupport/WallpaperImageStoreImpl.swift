//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class WallpaperImageStoreImpl: WallpaperImageStore {

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore

    public init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
    }

    public func setWallpaperImage(_ photo: UIImage?, for thread: TSThread, tx: DBWriteTransaction) throws {
        guard let rowId = thread.sqliteRowId else {
            throw OWSAssertionError("Inserting wallpaper for uninserted thread!")
        }
        try setWallpaperImage(photo, owner: .threadWallpaperImage(threadRowId: rowId), tx: tx)
    }

    public func setGlobalThreadWallpaperImage(_ photo: UIImage?, tx: DBWriteTransaction) throws {
        try setWallpaperImage(photo, owner: .globalThreadWallpaperImage, tx: tx)
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
        guard let fromReference = attachmentStore.fetchFirstReference(owner: .threadWallpaperImage(threadRowId: fromRowId), tx: tx) else {
            // Nothing to copy.
            return
        }

        // If the toThread had a wallpaper, remove it.
        if let toReference = attachmentStore.fetchFirstReference(owner: .threadWallpaperImage(threadRowId: toRowId), tx: tx) {
            try attachmentStore.removeOwner(.threadWallpaperImage(threadRowId: toRowId), for: toReference.attachmentRowId, tx: tx)
        }

        try attachmentStore.addOwner(
            duplicating: fromReference,
            withNewOwner: .threadWallpaperImage(threadRowId: toRowId),
            tx: tx
        )
    }

    public func resetAllWallpaperImages(tx: DBWriteTransaction) throws {
        try attachmentStore.removeAllThreadOwners(tx: tx)
    }

    // MARK: - Private

    private func dataSource(wallpaperImage photo: UIImage) throws -> AttachmentDataSource {
        guard let imageData = photo.jpegData(compressionQuality: 0.8) else {
            throw OWSAssertionError("Failed to get jpg data for wallpaper photo")
        }
        return .from(data: imageData, mimeType: MimeType.imageJpeg.rawValue)
    }

    private func setWallpaperImage(
        _ photo: UIImage?,
        owner: AttachmentReference.OwnerBuilder,
        tx: DBWriteTransaction
    ) throws {
        // First remove any existing wallpaper.
        if let existingReference = attachmentStore.fetchFirstReference(owner: owner.id, tx: tx) {
            try attachmentStore.removeOwner(owner.id, for: existingReference.attachmentRowId, tx: tx)
        }
        // Set the new image if any.
        if let photo {
            let dataSource = OwnedAttachmentDataSource(
                dataSource: try dataSource(wallpaperImage: photo),
                owner: owner
            )
            try attachmentManager.createAttachmentStream(consuming: dataSource, tx: tx)
        }
    }

    private func loadWallpaperImage(ownerId: AttachmentReference.OwnerId, tx: DBReadTransaction) -> UIImage? {
        guard
            let attachment = attachmentStore.fetchFirstReferencedAttachment(
                for: ownerId,
                tx: tx
            )
        else {
            return nil
        }
        return try? attachment.attachment.asStream()?.decryptedImage()
    }
}

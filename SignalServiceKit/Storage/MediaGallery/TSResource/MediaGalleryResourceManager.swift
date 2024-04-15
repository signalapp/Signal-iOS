//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public enum MediaGalleryResource {
    public struct ChangedResourceInfo {
        public var attachmentId: MediaGalleryResourceId
        public var threadGrdbId: Int64
        public var timestamp: UInt64
    }

    /// A notification for when an attachment stream becomes available (incoming attachment downloaded, or outgoing
    /// attachment loaded).
    ///
    /// The object of the notification is an array of ChangedResourceInfo values.
    /// When registering an observer for this notification, set the observed object to `nil`, meaning no filter.
    public static let newAttachmentsAvailableNotification =
        Notification.Name(rawValue: "SSKMediaGalleryFinderNewResourcesAvailable")

    /// A notification for when a downloaded attachment is removed.
    ///
    /// The object of the notification is an array of ChangedResourceInfo values.
    /// When registering an observer for this notification, set the observed object to `nil`, meaning no filter.
    public static let didRemoveAttachmentsNotification =
        Notification.Name(rawValue: "SSKMediaGalleryFinderDidRemoveResources")
}

public protocol MediaGalleryResourceManager {

    func didInsert(
        attachmentStream: ReferencedTSResourceStream,
        tx: DBWriteTransaction
    )

    func didRemove(
        attachmentStream: ReferencedTSResourceStream,
        tx: DBWriteTransaction
    )

    func didRemove(
        message: TSMessage,
        tx: DBWriteTransaction
    )
}

public final class MediaGalleryResourceManagerImpl: MediaGalleryResourceManager {

    public init() {}

    public func didInsert(
        attachmentStream: ReferencedTSResourceStream,
        tx: DBWriteTransaction
    ) {
        MediaGalleryRecordManager.didInsert(attachmentStream: attachmentStream, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func didRemove(
        attachmentStream: ReferencedTSResourceStream,
        tx: DBWriteTransaction
    ) {
        MediaGalleryRecordManager.didRemove(attachmentStream: attachmentStream, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func didRemove(
        message: TSMessage,
        tx: DBWriteTransaction
    ) {
        MediaGalleryRecordManager.didRemove(message: message, transaction: SDSDB.shimOnlyBridge(tx))
    }
}

#if TESTABLE_BUILD

public class MediaGalleryResourceManagerMock: MediaGalleryResourceManager {

    public init() {}

    open func didInsert(
        attachmentStream: ReferencedTSResourceStream,
        tx: DBWriteTransaction
    ) {}

    open func didRemove(
        attachmentStream: ReferencedTSResourceStream,
        tx: DBWriteTransaction
    ) {}

    open func didRemove(
        message: TSMessage,
        tx: DBWriteTransaction
    ) {}
}

#endif

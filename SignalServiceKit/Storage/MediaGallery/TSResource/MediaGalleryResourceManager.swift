//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class MediaGalleryResourceManager {

    public struct ChangedTSResourceInfo {
        public var uniqueId: String
        public var threadGrdbId: Int64
        public var timestamp: UInt64
    }

    /// A notification for when an attachment stream becomes available (incoming attachment downloaded, or outgoing
    /// attachment loaded).
    ///
    /// The object of the notification is an array of ChangedTSResourceInfo values.
    /// When registering an observer for this notification, set the observed object to `nil`, meaning no filter.
    public static let newAttachmentsAvailableNotification =
        Notification.Name(rawValue: "SSKMediaGalleryFinderNewResourcesAvailable")

    public class func didInsert(
        attachmentStream: TSAttachmentStream,
        transaction: SDSAnyWriteTransaction
    ) {
        MediaGalleryRecordManager.didInsert(attachmentStream: attachmentStream, transaction: transaction)
    }

    /// A notification for when a downloaded attachment is removed.
    ///
    /// The object of the notification is an array of ChangedTSResourceInfo values.
    /// When registering an observer for this notification, set the observed object to `nil`, meaning no filter.
    public static let didRemoveAttachmentsNotification =
        Notification.Name(rawValue: "SSKMediaGalleryFinderDidRemoveResources")

    public class func didRemove(
        attachmentStream: TSAttachmentStream,
        transaction: SDSAnyWriteTransaction
    ) {
        MediaGalleryRecordManager.didRemove(attachmentStream: attachmentStream, transaction: transaction)
    }

    public class func didRemove(
        message: TSMessage,
        transaction: SDSAnyWriteTransaction
    ) {
        MediaGalleryRecordManager.didRemove(message: message, transaction: transaction)
    }
}

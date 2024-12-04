//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// TODO: fire these notifications
/// Legacy TSAttachments used observation of the `media_gallery_item` table
/// to fire notifications and trigger updates when an attachment was:
/// a. Deleted
/// b. Stream created (e.g. local create for outgoing message)
/// c. Pointer updated to stream (by downloading)
/// All of the above require the media gallery to update its display.
///
/// MessageAttachmentReference does not support this type of observation simply.
/// For (a) we need to use GRDB.TransactionObserver, since they can be deleted
/// due to foreign key delete cascading. We need to filter only to deleted streams.
/// For (b) we can add a hook to swift code in AttachmentStore or AttachmentManager,
/// or we can use GRDB.TransactionObserver.
/// For (c) we need to use hooks in swift code in AttachmentDownloadManager.
///
/// All of the above are more expensive, so we probably wanna ditch firing
/// NSNotifications all the time and instead only observe/fire if the MediaGallery
/// is actually visible.
public struct MediaGalleryChangeInfo {
    public var referenceId: AttachmentReferenceId
    public var threadGrdbId: Int64
    public var timestamp: UInt64

    /// A notification for when an attachment stream becomes available (incoming attachment downloaded, or outgoing
    /// attachment loaded).
    ///
    /// The object of the notification is an array of MediaGalleryChangeInfo values.
    /// When registering an observer for this notification, set the observed object to `nil`, meaning no filter.
    public static let newAttachmentsAvailableNotification =
        Notification.Name(rawValue: "SSKMediaGalleryFinderNewResourcesAvailable")

    /// A notification for when a downloaded attachment is removed.
    ///
    /// The object of the notification is an array of MediaGalleryChangeInfo values.
    /// When registering an observer for this notification, set the observed object to `nil`, meaning no filter.
    public static let didRemoveAttachmentsNotification =
        Notification.Name(rawValue: "SSKMediaGalleryFinderDidRemoveResources")
}

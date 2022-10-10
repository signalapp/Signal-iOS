// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SignalCoreKit
import SessionUtilitiesKit
import SessionSnodeKit

/// This job deletes unused and orphaned data from the database as well as orphaned files from device storage
///
/// **Note:** When sheduling this job if no `Details` are provided (with a list of `typesToCollect`) then this job will
/// assume that it should be collecting all `Types`
public enum GarbageCollectionJob: JobExecutor {
    public static var maxFailureCount: Int = -1
    public static var requiresThreadId: Bool = false
    public static let requiresInteractionId: Bool = false
    public static let approxSixMonthsInSeconds: TimeInterval = (6 * 30 * 24 * 60 * 60)
    private static let minInteractionsToTrim: Int = 2000
    
    public static func run(
        _ job: Job,
        queue: DispatchQueue,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        /// Determine what types of data we want to collect (if we didn't provide any then assume we want to collect everything)
        ///
        /// **Note:** The reason we default to handle all cases (instead of just doing nothing in that case) is so the initial registration
        /// of the garbageCollection job never needs to be updated as we continue to add more types going forward
        let typesToCollect: [Types] = (job.details
            .map { try? JSONDecoder().decode(Details.self, from: $0) }?
            .typesToCollect)
            .defaulting(to: Types.allCases)
        let timestampNow: TimeInterval = Date().timeIntervalSince1970
        
        /// Only do a full collection if the job isn't the recurring one or it's been 23 hours since it last ran (23 hours so a user who opens the
        /// app at about the same time every day will trigger the garbage collection) - since this runs when the app becomes active we
        /// want to prevent it running to frequently (the app becomes active if a system alert, the notification center or the control panel
        /// are shown)
        let lastGarbageCollection: Date = UserDefaults.standard[.lastGarbageCollection]
            .defaulting(to: Date.distantPast)
        let finalTypesToCollection: Set<Types> = {
            guard
                job.behaviour != .recurringOnActive ||
                Date().timeIntervalSince(lastGarbageCollection) > (23 * 60 * 60)
            else {
                // Note: This should only contain the `Types` which are unlikely to ever cause
                // a startup delay (ie. avoid mass deletions and file management)
                return typesToCollect.asSet()
                    .intersection([
                        .threadTypingIndicators
                    ])
            }
            
            return typesToCollect.asSet()
        }()
        
        Storage.shared.writeAsync(
            updates: { db in
                /// Remove any typing indicators
                if finalTypesToCollection.contains(.threadTypingIndicators) {
                    _ = try ThreadTypingIndicator
                        .deleteAll(db)
                }
                
                /// Remove any expired controlMessageProcessRecords
                if finalTypesToCollection.contains(.expiredControlMessageProcessRecords) {
                    _ = try ControlMessageProcessRecord
                        .filter(ControlMessageProcessRecord.Columns.serverExpirationTimestamp <= timestampNow)
                        .deleteAll(db)
                }
                
                /// Remove any old open group messages - open group messages which are older than six months
                if finalTypesToCollection.contains(.oldOpenGroupMessages) && db[.trimOpenGroupMessagesOlderThanSixMonths] {
                    let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                    let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
                    let threadIdLiteral: SQL = SQL(stringLiteral: Interaction.Columns.threadId.name)
                    let minInteractionsToTrimSql: SQL = SQL("\(GarbageCollectionJob.minInteractionsToTrim)")
                    
                    try db.execute(literal: """
                        DELETE FROM \(Interaction.self)
                        WHERE \(Column.rowID) IN (
                            SELECT \(interaction.alias[Column.rowID])
                            FROM \(Interaction.self)
                            JOIN \(SessionThread.self) ON (
                                \(SQL("\(thread[.variant]) = \(SessionThread.Variant.openGroup)")) AND
                                \(thread[.id]) = \(interaction[.threadId])
                            )
                            JOIN (
                                SELECT
                                    COUNT(\(interaction.alias[Column.rowID])) AS interactionCount,
                                    \(interaction[.threadId])
                                FROM \(Interaction.self)
                                GROUP BY \(interaction[.threadId])
                            ) AS interactionInfo ON interactionInfo.\(threadIdLiteral) = \(interaction[.threadId])
                            WHERE (
                                \(interaction[.timestampMs]) < \(timestampNow - approxSixMonthsInSeconds) AND
                                interactionInfo.interactionCount >= \(minInteractionsToTrimSql)
                            )
                        )
                    """)
                }
                
                /// Orphaned jobs - jobs which have had their threads or interactions removed
                if finalTypesToCollection.contains(.orphanedJobs) {
                    let job: TypedTableAlias<Job> = TypedTableAlias()
                    let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
                    let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                    
                    try db.execute(literal: """
                        DELETE FROM \(Job.self)
                        WHERE \(Column.rowID) IN (
                            SELECT \(job.alias[Column.rowID])
                            FROM \(Job.self)
                            LEFT JOIN \(SessionThread.self) ON \(thread[.id]) = \(job[.threadId])
                            LEFT JOIN \(Interaction.self) ON \(interaction[.id]) = \(job[.interactionId])
                            WHERE (
                                (
                                    \(job[.threadId]) IS NOT NULL AND
                                    \(thread[.id]) IS NULL
                                ) OR (
                                    \(job[.interactionId]) IS NOT NULL AND
                                    \(interaction[.id]) IS NULL
                                )
                            )
                        )
                    """)
                }
                
                /// Orphaned link previews - link previews which have no interactions with matching url & rounded timestamps
                if finalTypesToCollection.contains(.orphanedLinkPreviews) {
                    let linkPreview: TypedTableAlias<LinkPreview> = TypedTableAlias()
                    let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                    
                    try db.execute(literal: """
                        DELETE FROM \(LinkPreview.self)
                        WHERE \(Column.rowID) IN (
                            SELECT \(linkPreview.alias[Column.rowID])
                            FROM \(LinkPreview.self)
                            LEFT JOIN \(Interaction.self) ON (
                                \(interaction[.linkPreviewUrl]) = \(linkPreview[.url]) AND
                                \(Interaction.linkPreviewFilterLiteral())
                            )
                            WHERE \(interaction[.id]) IS NULL
                        )
                    """)
                }
                
                /// Orphaned open groups - open groups which are no longer associated to a thread (except for the session-run ones for which
                /// we want cached image data even if the user isn't in the group)
                if finalTypesToCollection.contains(.orphanedOpenGroups) {
                    let openGroup: TypedTableAlias<OpenGroup> = TypedTableAlias()
                    let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
                    
                    try db.execute(literal: """
                        DELETE FROM \(OpenGroup.self)
                        WHERE \(Column.rowID) IN (
                            SELECT \(openGroup.alias[Column.rowID])
                            FROM \(OpenGroup.self)
                            LEFT JOIN \(SessionThread.self) ON \(thread[.id]) = \(openGroup[.threadId])
                            WHERE (
                                \(thread[.id]) IS NULL AND
                                \(SQL("\(openGroup[.server]) != \(OpenGroupAPI.defaultServer.lowercased())"))
                            )
                        )
                    """)
                }
                
                /// Orphaned open group capabilities - capabilities which have no existing open groups with the same server
                if finalTypesToCollection.contains(.orphanedOpenGroupCapabilities) {
                    let capability: TypedTableAlias<Capability> = TypedTableAlias()
                    let openGroup: TypedTableAlias<OpenGroup> = TypedTableAlias()
                    
                    try db.execute(literal: """
                        DELETE FROM \(Capability.self)
                        WHERE \(Column.rowID) IN (
                            SELECT \(capability.alias[Column.rowID])
                            FROM \(Capability.self)
                            LEFT JOIN \(OpenGroup.self) ON \(openGroup[.server]) = \(capability[.openGroupServer])
                            WHERE \(openGroup[.threadId]) IS NULL
                        )
                    """)
                }
                
                /// Orphaned blinded id lookups - lookups which have no existing threads or approval/block settings for either blinded/un-blinded id
                if finalTypesToCollection.contains(.orphanedBlindedIdLookups) {
                    let blindedIdLookup: TypedTableAlias<BlindedIdLookup> = TypedTableAlias()
                    let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
                    let contact: TypedTableAlias<Contact> = TypedTableAlias()
                    
                    try db.execute(literal: """
                        DELETE FROM \(BlindedIdLookup.self)
                        WHERE \(Column.rowID) IN (
                            SELECT \(blindedIdLookup.alias[Column.rowID])
                            FROM \(BlindedIdLookup.self)
                            LEFT JOIN \(SessionThread.self) ON (
                                \(thread[.id]) = \(blindedIdLookup[.blindedId]) OR
                                \(thread[.id]) = \(blindedIdLookup[.sessionId])
                            )
                            LEFT JOIN \(Contact.self) ON (
                                \(contact[.id]) = \(blindedIdLookup[.blindedId]) OR
                                \(contact[.id]) = \(blindedIdLookup[.sessionId])
                            )
                            WHERE (
                                \(thread[.id]) IS NULL AND
                                \(contact[.id]) IS NULL
                            )
                        )
                    """)
                }
                
                /// Approved blinded contact records - once a blinded contact has been approved there is no need to keep the blinded
                /// contact record around anymore
                if finalTypesToCollection.contains(.approvedBlindedContactRecords) {
                    let contact: TypedTableAlias<Contact> = TypedTableAlias()
                    let blindedIdLookup: TypedTableAlias<BlindedIdLookup> = TypedTableAlias()

                    try db.execute(literal: """
                        DELETE FROM \(Contact.self)
                        WHERE \(Column.rowID) IN (
                            SELECT \(contact.alias[Column.rowID])
                            FROM \(Contact.self)
                            LEFT JOIN \(BlindedIdLookup.self) ON (
                                \(blindedIdLookup[.blindedId]) = \(contact[.id]) AND
                                \(blindedIdLookup[.sessionId]) IS NOT NULL
                            )
                            WHERE \(blindedIdLookup[.sessionId]) IS NOT NULL
                        )
                    """)
                }
                
                /// Orphaned attachments - attachments which have no related interactions, quotes or link previews
                if finalTypesToCollection.contains(.orphanedAttachments) {
                    let attachment: TypedTableAlias<Attachment> = TypedTableAlias()
                    let quote: TypedTableAlias<Quote> = TypedTableAlias()
                    let linkPreview: TypedTableAlias<LinkPreview> = TypedTableAlias()
                    let interactionAttachment: TypedTableAlias<InteractionAttachment> = TypedTableAlias()
                    
                    try db.execute(literal: """
                        DELETE FROM \(Attachment.self)
                        WHERE \(Column.rowID) IN (
                            SELECT \(attachment.alias[Column.rowID])
                            FROM \(Attachment.self)
                            LEFT JOIN \(Quote.self) ON \(quote[.attachmentId]) = \(attachment[.id])
                            LEFT JOIN \(LinkPreview.self) ON \(linkPreview[.attachmentId]) = \(attachment[.id])
                            LEFT JOIN \(InteractionAttachment.self) ON \(interactionAttachment[.attachmentId]) = \(attachment[.id])
                            WHERE (
                                \(quote[.attachmentId]) IS NULL AND
                                \(linkPreview[.url]) IS NULL AND
                                \(interactionAttachment[.attachmentId]) IS NULL
                            )
                        )
                    """)
                }
                
                if finalTypesToCollection.contains(.orphanedProfiles) {
                    let profile: TypedTableAlias<Profile> = TypedTableAlias()
                    let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
                    let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                    let quote: TypedTableAlias<Quote> = TypedTableAlias()
                    let groupMember: TypedTableAlias<GroupMember> = TypedTableAlias()
                    let contact: TypedTableAlias<Contact> = TypedTableAlias()
                    let blindedIdLookup: TypedTableAlias<BlindedIdLookup> = TypedTableAlias()
                    
                    try db.execute(literal: """
                        DELETE FROM \(Profile.self)
                        WHERE \(Column.rowID) IN (
                            SELECT \(profile.alias[Column.rowID])
                            FROM \(Profile.self)
                            LEFT JOIN \(SessionThread.self) ON \(thread[.id]) = \(profile[.id])
                            LEFT JOIN \(Interaction.self) ON \(interaction[.authorId]) = \(profile[.id])
                            LEFT JOIN \(Quote.self) ON \(quote[.authorId]) = \(profile[.id])
                            LEFT JOIN \(GroupMember.self) ON \(groupMember[.profileId]) = \(profile[.id])
                            LEFT JOIN \(Contact.self) ON \(contact[.id]) = \(profile[.id])
                            LEFT JOIN \(BlindedIdLookup.self) ON (
                                blindedIdLookup.blindedId = \(profile[.id]) OR
                                blindedIdLookup.sessionId = \(profile[.id])
                            )
                            WHERE (
                                \(thread[.id]) IS NULL AND
                                \(interaction[.authorId]) IS NULL AND
                                \(quote[.authorId]) IS NULL AND
                                \(groupMember[.profileId]) IS NULL AND
                                \(contact[.id]) IS NULL AND
                                \(blindedIdLookup[.blindedId]) IS NULL
                            )
                        )
                    """)
                }
            },
            completion: { _, _ in
                // Dispatch async so we can swap from the write queue to a read one (we are done writing)
                queue.async {
                    // Retrieve a list of all valid attachmnet and avatar file paths
                    struct FileInfo {
                        let attachmentLocalRelativePaths: Set<String>
                        let profileAvatarFilenames: Set<String>
                    }
                    
                    let maybeFileInfo: FileInfo? = Storage.shared.read { db -> FileInfo in
                        var attachmentLocalRelativePaths: Set<String> = []
                        var profileAvatarFilenames: Set<String> = []
                        
                        /// Orphaned attachment files - attachment files which don't have an associated record in the database
                        if finalTypesToCollection.contains(.orphanedAttachmentFiles) {
                            /// **Note:** Thumbnails are stored in the `NSCachesDirectory` directory which should be automatically manage
                            /// it's own garbage collection so we can just ignore it according to the various comments in the following stack overflow
                            /// post, the directory will be cleared during app updates as well as if the system is running low on memory (if the app isn't running)
                            /// https://stackoverflow.com/questions/6879860/when-are-files-from-nscachesdirectory-removed
                            attachmentLocalRelativePaths = try Attachment
                                .select(.localRelativeFilePath)
                                .filter(Attachment.Columns.localRelativeFilePath != nil)
                                .asRequest(of: String.self)
                                .fetchSet(db)
                        }

                        /// Orphaned profile avatar files - profile avatar files which don't have an associated record in the database
                        if finalTypesToCollection.contains(.orphanedProfileAvatars) {
                            profileAvatarFilenames = try Profile
                                .select(.profilePictureFileName)
                                .filter(Profile.Columns.profilePictureFileName != nil)
                                .asRequest(of: String.self)
                                .fetchSet(db)
                        }
                        
                        return FileInfo(
                            attachmentLocalRelativePaths: attachmentLocalRelativePaths,
                            profileAvatarFilenames: profileAvatarFilenames
                        )
                    }
                    
                    // If we couldn't get the file lists then fail (invalid state and don't want to delete all attachment/profile files)
                    guard let fileInfo: FileInfo = maybeFileInfo else {
                        failure(job, StorageError.generic, false)
                        return
                    }
                        
                    var deletionErrors: [Error] = []
                    
                    // Orphaned attachment files (actual deletion)
                    if finalTypesToCollection.contains(.orphanedAttachmentFiles) {
                        // Note: Looks like in order to recursively look through files we need to use the
                        // enumerator method
                        let fileEnumerator = FileManager.default.enumerator(
                            at: URL(fileURLWithPath: Attachment.attachmentsFolder),
                            includingPropertiesForKeys: nil,
                            options: .skipsHiddenFiles  // Ignore the `.DS_Store` for the simulator
                        )
                        
                        let allAttachmentFilePaths: Set<String> = (fileEnumerator?
                            .allObjects
                            .compactMap { Attachment.localRelativeFilePath(from: ($0 as? URL)?.path) })
                            .defaulting(to: [])
                            .asSet()
                        
                        // Note: Directories will have their own entries in the list, if there is a folder with content
                        // the file will include the directory in it's path with a forward slash so we can use this to
                        // distinguish empty directories from ones with content so we don't unintentionally delete a
                        // directory which contains content to keep as well as delete (directories which end up empty after
                        // this clean up will be removed during the next run)
                        let directoryNamesContainingContent: [String] = allAttachmentFilePaths
                            .filter { path -> Bool in path.contains("/") }
                            .compactMap { path -> String? in path.components(separatedBy: "/").first }
                        let orphanedAttachmentFiles: Set<String> = allAttachmentFilePaths
                            .subtracting(fileInfo.attachmentLocalRelativePaths)
                            .subtracting(directoryNamesContainingContent)
                        
                        orphanedAttachmentFiles.forEach { filepath in
                            // We don't want a single deletion failure to block deletion of the other files so try
                            // each one and store the error to be used to determine success/failure of the job
                            do {
                                try FileManager.default.removeItem(
                                    atPath: URL(fileURLWithPath: Attachment.attachmentsFolder)
                                        .appendingPathComponent(filepath)
                                        .path
                                )
                            }
                            catch { deletionErrors.append(error) }
                        }
                        
                        SNLog("[GarbageCollectionJob] Removed \(orphanedAttachmentFiles.count) orphaned attachment\(orphanedAttachmentFiles.count == 1 ? "" : "s")")
                    }
                    
                    // Orphaned profile avatar files (actual deletion)
                    if finalTypesToCollection.contains(.orphanedProfileAvatars) {
                        let allAvatarProfileFilenames: Set<String> = (try? FileManager.default
                            .contentsOfDirectory(atPath: ProfileManager.sharedDataProfileAvatarsDirPath))
                            .defaulting(to: [])
                            .asSet()
                        let orphanedAvatarFiles: Set<String> = allAvatarProfileFilenames
                            .subtracting(fileInfo.profileAvatarFilenames)
                        
                        orphanedAvatarFiles.forEach { filename in
                            // We don't want a single deletion failure to block deletion of the other files so try
                            // each one and store the error to be used to determine success/failure of the job
                            do {
                                try FileManager.default.removeItem(
                                    atPath: ProfileManager.profileAvatarFilepath(filename: filename)
                                )
                            }
                            catch { deletionErrors.append(error) }
                        }
                        
                        SNLog("[GarbageCollectionJob] Removed \(orphanedAvatarFiles.count) orphaned avatar image\(orphanedAvatarFiles.count == 1 ? "" : "s")")
                    }
                    
                    // Report a single file deletion as a job failure (even if other content was successfully removed)
                    guard deletionErrors.isEmpty else {
                        failure(job, (deletionErrors.first ?? StorageError.generic), false)
                        return
                    }
                    
                    // If we did a full collection then update the 'lastGarbageCollection' date to
                    // prevent a full collection from running again in the next 23 hours
                    if job.behaviour == .recurringOnActive && Date().timeIntervalSince(lastGarbageCollection) > (23 * 60 * 60) {
                        UserDefaults.standard[.lastGarbageCollection] = Date()
                    }
                    
                    success(job, false)
                }
            }
        )
    }
}

// MARK: - GarbageCollectionJob.Details

extension GarbageCollectionJob {
    public enum Types: Codable, CaseIterable {
        case expiredControlMessageProcessRecords
        case threadTypingIndicators
        case oldOpenGroupMessages
        case orphanedJobs
        case orphanedLinkPreviews
        case orphanedOpenGroups
        case orphanedOpenGroupCapabilities
        case orphanedBlindedIdLookups
        case approvedBlindedContactRecords
        case orphanedProfiles
        case orphanedAttachments
        case orphanedAttachmentFiles
        case orphanedProfileAvatars
    }
    
    public struct Details: Codable {
        public let typesToCollect: [Types]
        
        public init(typesToCollect: [Types] = Types.allCases) {
            self.typesToCollect = typesToCollect
        }
    }
}

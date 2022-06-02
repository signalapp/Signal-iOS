// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SignalCoreKit
import SessionUtilitiesKit
import SessionSnodeKit

public enum GarbageCollectionJob: JobExecutor {
    public static var maxFailureCount: Int = -1
    public static var requiresThreadId: Bool = false
    public static let requiresInteractionId: Bool = false
    private static let approxSixMonthsInSeconds: TimeInterval = (6 * 30 * 24 * 60 * 60)
    
    public static func run(
        _ job: Job,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        guard
            let detailsData: Data = job.details,
            let details: Details = try? JSONDecoder().decode(Details.self, from: detailsData)
        else {
            failure(job, JobRunnerError.missingRequiredDetails, false)
            return
        }
        
        // If there are no types to collect then complete the job (and never run again - it doesn't do anything)
        guard !details.typesToCollect.isEmpty else {
            success(job, true)
            return
        }
        
        let timestampNow: TimeInterval = Date().timeIntervalSince1970
        var attachmentLocalRelativePaths: Set<String> = []
        var profileAvatarFilenames: Set<String> = []
        
        GRDBStorage.shared.writeAsync(
            updates: { db in
                // Remove any expired controlMessageProcessRecords
                if details.typesToCollect.contains(.expiredControlMessageProcessRecords) {
                    _ = try ControlMessageProcessRecord
                        .filter(ControlMessageProcessRecord.Columns.serverExpirationTimestamp <= timestampNow)
                        .deleteAll(db)
                }
                
                // Remove any typing indicators
                if details.typesToCollect.contains(.threadTypingIndicators) {
                    _ = try ThreadTypingIndicator
                        .deleteAll(db)
                }
                
                // Remove any typing indicators
                if details.typesToCollect.contains(.oldOpenGroupMessages) {
                    let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                    let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
                    
                    try db.execute(literal: """
                        DELETE FROM \(Interaction.self)
                        WHERE \(Column.rowID) IN (
                            SELECT \(interaction.alias[Column.rowID])
                            FROM \(Interaction.self)
                            JOIN \(SessionThread.self) ON (
                                \(SQL("\(thread[.variant]) = \(SessionThread.Variant.openGroup)")) AND
                                \(thread[.id]) = \(interaction[.threadId])
                            )
                            WHERE \(interaction[.timestampMs]) < \(timestampNow - approxSixMonthsInSeconds)
                        )
                    """)
                }
                
                // Orphaned jobs
                if details.typesToCollect.contains(.orphanedJobs) {
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
                
                // Orphaned link previews
                if details.typesToCollect.contains(.orphanedLinkPreviews) {
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
                
                // Orphaned attachments
                if details.typesToCollect.contains(.orphanedAttachments) {
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
                
                // Orphaned attachment files
                if details.typesToCollect.contains(.orphanedAttachmentFiles) {
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
                
                // Orphaned profile avatar files
                if details.typesToCollect.contains(.orphanedProfileAvatars) {
                    profileAvatarFilenames = try Profile
                        .select(.profilePictureFileName)
                        .filter(Profile.Columns.profilePictureFileName != nil)
                        .asRequest(of: String.self)
                        .fetchSet(db)
                }
            },
            completion: { _, _ in
                var deletionErrors: [Error] = []
                
                // Orphaned attachment files (actual deletion)
                if details.typesToCollect.contains(.orphanedAttachmentFiles) {
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
                        .subtracting(attachmentLocalRelativePaths)
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
                }
                
                // Orphaned profile avatar files (actual deletion)
                if details.typesToCollect.contains(.orphanedProfileAvatars) {
                    let allAvatarProfileFilenames: Set<String> = (try? FileManager.default
                        .contentsOfDirectory(atPath: ProfileManager.sharedDataProfileAvatarsDirPath))
                        .defaulting(to: [])
                        .asSet()
                    let orphanedAvatarFiles: Set<String> = allAvatarProfileFilenames
                        .subtracting(profileAvatarFilenames)
                    
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
                }
                
                // Report a single file deletion as a job failure (even if other content was successfully removed)
                guard deletionErrors.isEmpty else {
                    failure(job, (deletionErrors.first ?? StorageError.generic), false)
                    return
                }
                
                success(job, false)
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

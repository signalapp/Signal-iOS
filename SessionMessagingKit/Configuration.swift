import Foundation
import SessionUtilitiesKit

public enum SNMessagingKit { // Just to make the external API nice
    public static func migrations() -> TargetMigrations {
        return TargetMigrations(
            identifier: .messagingKit,
            migrations: [
                [
                    _001_InitialSetupMigration.self,
                    _002_SetupStandardJobs.self
                ],
                [
                    _003_YDBToGRDBMigration.self
                ],
                [
                    _004_RemoveLegacyYDB.self
                ],
                [
                    _005_FixDeletedMessageReadState.self,
                    _006_FixHiddenModAdminSupport.self,
                    _007_HomeQueryOptimisationIndexes.self
                ],
                [
                    _008_EmojiReacts.self,
                    _009_OpenGroupPermission.self
                ]
            ]
        )
    }
    
    public static func configure() {
        // Configure the job executors
        JobRunner.add(executor: DisappearingMessagesJob.self, for: .disappearingMessages)
        JobRunner.add(executor: FailedMessageSendsJob.self, for: .failedMessageSends)
        JobRunner.add(executor: FailedAttachmentDownloadsJob.self, for: .failedAttachmentDownloads)
        JobRunner.add(executor: UpdateProfilePictureJob.self, for: .updateProfilePicture)
        JobRunner.add(executor: RetrieveDefaultOpenGroupRoomsJob.self, for: .retrieveDefaultOpenGroupRooms)
        JobRunner.add(executor: GarbageCollectionJob.self, for: .garbageCollection)
        JobRunner.add(executor: MessageSendJob.self, for: .messageSend)
        JobRunner.add(executor: MessageReceiveJob.self, for: .messageReceive)
        JobRunner.add(executor: NotifyPushServerJob.self, for: .notifyPushServer)
        JobRunner.add(executor: SendReadReceiptsJob.self, for: .sendReadReceipts)
        JobRunner.add(executor: AttachmentDownloadJob.self, for: .attachmentDownload)
        JobRunner.add(executor: AttachmentUploadJob.self, for: .attachmentUpload)
    }
}

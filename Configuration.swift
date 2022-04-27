import Foundation
import SessionUtilitiesKit

@objc
public final class SNMessagingKitConfiguration : NSObject {
    public let storage: SessionMessagingKitStorageProtocol

    @objc public static var shared: SNMessagingKitConfiguration!

    fileprivate init(storage: SessionMessagingKitStorageProtocol) {
        self.storage = storage
    }
}

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
                ]
            ]
        )
    }
    
    public static func configure(storage: SessionMessagingKitStorageProtocol) {
        // Configure the job executors
        JobRunner.add(executor: DisappearingMessagesJob.self, for: .disappearingMessages)
        JobRunner.add(executor: FailedMessagesJob.self, for: .failedMessages)
        JobRunner.add(executor: FailedAttachmentDownloadsJob.self, for: .failedAttachmentDownloads)
        JobRunner.add(executor: UpdateProfilePictureJob.self, for: .updateProfilePicture)
        JobRunner.add(executor: RetrieveDefaultOpenGroupRoomsJob.self, for: .retrieveDefaultOpenGroupRooms)
        JobRunner.add(executor: MessageSendJob.self, for: .messageSend)
        JobRunner.add(executor: MessageReceiveJob.self, for: .messageReceive)
        JobRunner.add(executor: NotifyPushServerJob.self, for: .notifyPushServer)
        JobRunner.add(executor: SendReadReceiptsJob.self, for: .sendReadReceipts)
        JobRunner.add(executor: AttachmentDownloadJob.self, for: .attachmentDownload)
        
        SNMessagingKitConfiguration.shared = SNMessagingKitConfiguration(storage: storage)
    }
}

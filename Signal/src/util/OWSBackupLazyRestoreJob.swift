//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

@objc
public class OWSBackupLazyRestoreJob: NSObject {

    let TAG = "[OWSBackupLazyRestoreJob]"

    let primaryStorage: OWSPrimaryStorage

    private var jobTempDirPath: String?

    deinit {
        if let jobTempDirPath = self.jobTempDirPath {
            DispatchQueue.global().async {
                OWSFileSystem.deleteFile(jobTempDirPath)
            }
        }
    }

    @objc
    public class func run() {
        OWSBackupLazyRestoreJob().run()
    }

    public override init() {
        self.primaryStorage = OWSPrimaryStorage.shared()
    }

    private func run() {
        AssertIsOnMainThread()

        DispatchQueue.global().async {
            self.restoreAttachments()
        }
    }

    private func restoreAttachments() {
        let temporaryDirectory = NSTemporaryDirectory()
        let jobTempDirPath = (temporaryDirectory as NSString).appendingPathComponent(NSUUID().uuidString)
        //            let jobTempDirPath = temporaryDirectory.appendingPathComponent(UUID().uuidString)

        guard OWSFileSystem.ensureDirectoryExists(jobTempDirPath) else {
            Logger.error("\(TAG) could not create temp directory.")
            return
        }

        self.jobTempDirPath = jobTempDirPath

        let backupIO = OWSBackupIO(jobTempDirPath: jobTempDirPath)

        let attachmentIds = OWSBackup.shared().attachmentIdsForLazyRestore()
        self.tryToRestoreNextAttachment(attachmentIds: attachmentIds, backupIO: backupIO)
    }

    private func tryToRestoreNextAttachment(attachmentIds: [String], backupIO: OWSBackupIO) {
        var attachmentIdsCopy = attachmentIds
        guard let attachmentId = attachmentIdsCopy.last else {
            // This job is done.
            Logger.verbose("\(TAG) job is done.")
            return
        }
        attachmentIdsCopy.removeLast()
        guard let attachment = TSAttachmentStream.fetch(uniqueId: attachmentId) else {
            Logger.warn("\(TAG) could not load attachment.")
            // Not necessarily an error.
            // The attachment might have been deleted since the job began.
            // Continue trying to restore the other attachments.
            tryToRestoreNextAttachment(attachmentIds: attachmentIds, backupIO: backupIO)
            return
        }
        OWSBackup.shared().lazyRestoreAttachment(attachment,
                                                 backupIO: backupIO,
                                                 completion: { (success) in
                                                    if success {
                                                        Logger.info("\(self.TAG) restored attachment.")
                                                    } else {
                                                        Logger.warn("\(self.TAG) could not restore attachment.")
                                                    }
                                                // Continue trying to restore the other attachments.
                                                self.tryToRestoreNextAttachment(attachmentIds: attachmentIdsCopy, backupIO: backupIO)
        })

    }
}

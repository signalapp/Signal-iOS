//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import CloudKit

@objc public class OWSBackupAPI: NSObject {
    @objc
    public class func recordIdForTest() -> String {
        return "test-\(NSUUID().uuidString)"
    }

    @objc
    public class func recordIdForAttachmentStream(value: TSAttachmentStream) -> String {
        guard let uniqueId = value.uniqueId else {
            owsFail("Database entity missing uniqueId.")
            return "unknown"
        }
        return "attachment-stream-\(uniqueId)"
    }

    @objc
    public class func saveTestFileToCloud(fileUrl: URL,
                                          success: @escaping (String) -> Swift.Void,
                                          failure: @escaping (Error) -> Swift.Void) {
        saveFileToCloud(fileUrl: fileUrl,
                        recordId: recordIdForTest(),
                        recordType: "test",
                        success: success,
                        failure: failure)
    }

    @objc
    public class func saveBackupFileToCloud(fileUrl: URL,
                                            success: @escaping (String) -> Swift.Void,
                                            failure: @escaping (Error) -> Swift.Void) {
        saveFileToCloud(fileUrl: fileUrl,
                        recordId: NSUUID().uuidString,
                        recordType: "backupFile",
                        success: success,
                        failure: failure)
    }

    @objc
    public class func saveFileToCloud(fileUrl: URL,
                                      recordId: String,
                                      recordType: String,
                                      success: @escaping (String) -> Swift.Void,
                                      failure: @escaping (Error) -> Swift.Void) {
        let recordID = CKRecordID(recordName: recordId)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        let asset = CKAsset(fileURL: fileUrl)
        record["payload"] = asset

        saveRecordToCloud(record: record,
                          success: success,
                          failure: failure)
    }

    @objc
    public class func saveRecordToCloud(record: CKRecord,
                                        success: @escaping (String) -> Swift.Void,
                                        failure: @escaping (Error) -> Swift.Void) {

        let myContainer = CKContainer.default()
        let privateDatabase = myContainer.privateCloudDatabase
        privateDatabase.save(record) {
            (record, error) in

            if let error = error {
                Logger.error("\(self.logTag) error saving record: \(error)")
                failure(error)
            } else {
                guard let recordName = record?.recordID.recordName else {
                    Logger.error("\(self.logTag) error retrieving saved record's name.")
                    failure(OWSErrorWithCodeDescription(.exportBackupError,
                                                        NSLocalizedString("BACKUP_EXPORT_ERROR_SAVE_FILE_TO_CLOUD_FAILED",
                                                                          comment: "Error indicating the a backup export failed to save a file to the cloud.")))
                    return
                }
                Logger.info("\(self.logTag) saved record.")
                success(recordName)
            }
        }
    }

    @objc
    public class func checkCloudKitAccess(completion: @escaping (Bool) -> Swift.Void) {
        CKContainer.default().accountStatus(completionHandler: { (accountStatus, error) in
            DispatchQueue.main.async {
                switch accountStatus {
                case .couldNotDetermine:
                    Logger.error("\(self.logTag) could not determine CloudKit account status:\(String(describing: error)).")
                    OWSAlerts.showErrorAlert(withMessage: NSLocalizedString("CLOUDKIT_STATUS_COULD_NOT_DETERMINE", comment: "Error indicating that the app could not determine that user's CloudKit account status"))
                    completion(false)
                case .noAccount:
                    Logger.error("\(self.logTag) no CloudKit account.")
                    OWSAlerts.showErrorAlert(withMessage: NSLocalizedString("CLOUDKIT_STATUS_NO_ACCOUNT", comment: "Error indicating that user does not have an iCloud account."))
                    completion(false)
                case .restricted:
                    Logger.error("\(self.logTag) restricted CloudKit account.")
                    OWSAlerts.showErrorAlert(withMessage: NSLocalizedString("CLOUDKIT_STATUS_RESTRICTED", comment: "Error indicating that the app was prevented from accessing the user's CloudKit account."))
                    completion(false)
                case .available:
                    completion(true)
                }
            }
        })
    }
}

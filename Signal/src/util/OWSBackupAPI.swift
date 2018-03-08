//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import CloudKit

@objc public class OWSBackupAPI: NSObject {

    // If we change the record types, we need to ensure indices
    // are configured properly in the CloudKit dashboard.
    static let signalBackupRecordType = "signalBackup"
    static let manifestRecordName = "manifest"
    static let payloadKey = "payload"

    @objc
    public class func recordIdForTest() -> String {
        return "test-\(NSUUID().uuidString)"
    }

    @objc
    public class func saveTestFileToCloud(fileUrl: URL,
                                          success: @escaping (String) -> Swift.Void,
                                          failure: @escaping (Error) -> Swift.Void) {
        saveFileToCloud(fileUrl: fileUrl,
                        recordName: NSUUID().uuidString,
                        recordType: signalBackupRecordType,
                        success: success,
                        failure: failure)
    }

    // "Ephemeral" files are specific to this backup export and will always need to
    // be saved.  For example, a complete image of the database is exported each time.
    // We wouldn't want to overwrite previous images until the entire backup export is
    // complete.
    @objc
    public class func saveEphemeralDatabaseFileToCloud(fileUrl: URL,
                                                       success: @escaping (String) -> Swift.Void,
                                                       failure: @escaping (Error) -> Swift.Void) {
        saveFileToCloud(fileUrl: fileUrl,
                        recordName: NSUUID().uuidString,
                        recordType: signalBackupRecordType,
                        success: success,
                        failure: failure)
    }

    // "Persistent" files may be shared between backup export; they should only be saved
    // once.  For example, attachment files should only be uploaded once.  Subsequent
    // backups can reuse the same record.
    @objc
    public class func savePersistentFileOnceToCloud(fileId: String,
                                                    fileUrlBlock: @escaping (Swift.Void) -> URL?,
                                                    success: @escaping (String) -> Swift.Void,
                                                    failure: @escaping (Error) -> Swift.Void) {
        saveFileOnceToCloud(recordName: "persistentFile-\(fileId)",
            recordType: signalBackupRecordType,
            fileUrlBlock: fileUrlBlock,
            success: success,
            failure: failure)
    }

    //    @objc
    //    public class func upsertAttachmentToCloud(fileUrl: URL,
    //                                                success: @escaping (String) -> Swift.Void,
    //                                                failure: @escaping (Error) -> Swift.Void) {
    //        // We want to use a well-known record id and type for manifest files.
    //        upsertFileToCloud(fileUrl: fileUrl,
    //                          recordName: manifestRecordName,
    //                          recordType: signalBackupRecordType,
    //                          success: success,
    //                          failure: failure)
    //    }

    @objc
    public class func upsertManifestFileToCloud(fileUrl: URL,
                                                success: @escaping (String) -> Swift.Void,
                                                failure: @escaping (Error) -> Swift.Void) {
        // We want to use a well-known record id and type for manifest files.
        upsertFileToCloud(fileUrl: fileUrl,
                          recordName: manifestRecordName,
                          recordType: signalBackupRecordType,
                          success: success,
                          failure: failure)
    }

    @objc
    public class func saveFileToCloud(fileUrl: URL,
                                      recordName: String,
                                      recordType: String,
                                      success: @escaping (String) -> Swift.Void,
                                      failure: @escaping (Error) -> Swift.Void) {
        let recordID = CKRecordID(recordName: recordName)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        let asset = CKAsset(fileURL: fileUrl)
        record[payloadKey] = asset

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
    public class func deleteRecordFromCloud(recordName: String,
                                            success: @escaping (Swift.Void) -> Swift.Void,
                                            failure: @escaping (Error) -> Swift.Void) {

        let recordID = CKRecordID(recordName: recordName)

        let myContainer = CKContainer.default()
        let privateDatabase = myContainer.privateCloudDatabase
        privateDatabase.delete(withRecordID: recordID) {
            (record, error) in

            if let error = error {
                Logger.error("\(self.logTag) error deleting record: \(error)")
                failure(error)
            } else {
                Logger.info("\(self.logTag) deleted record.")
                success()
            }
        }
    }

    // Compare:
    // * An "upsert" creates a new record if none exists and
    //   or updates if there is an existing record.
    // * A "save once" creates a new record if none exists and
    //   does nothing if there is an existing record.
    @objc
    public class func upsertFileToCloud(fileUrl: URL,
                                        recordName: String,
                                        recordType: String,
                                        success: @escaping (String) -> Swift.Void,
                                        failure: @escaping (Error) -> Swift.Void) {

        checkForFileInCloud(recordName: recordName,
                            success: { (record) in
                                if let record = record {
                                    // Record found, updating existing record.
                                    let asset = CKAsset(fileURL: fileUrl)
                                    record[payloadKey] = asset
                                    saveRecordToCloud(record: record,
                                                      success: success,
                                                      failure: failure)
                                } else {
                                    // No record found, saving new record.
                                    saveFileToCloud(fileUrl: fileUrl,
                                                    recordName: recordName,
                                                    recordType: recordType,
                                                    success: success,
                                                    failure: failure)
                                }
        },
                            failure: failure)
    }

    // Compare:
    // * An "upsert" creates a new record if none exists and
    //   or updates if there is an existing record.
    // * A "save once" creates a new record if none exists and
    //   does nothing if there is an existing record.
    @objc
    public class func saveFileOnceToCloud(recordName: String,
                                          recordType: String,
                                          fileUrlBlock: @escaping (Swift.Void) -> URL?,
                                          success: @escaping (String) -> Swift.Void,
                                          failure: @escaping (Error) -> Swift.Void) {

        checkForFileInCloud(recordName: recordName,
                            success: { (record) in
                                if record != nil {
                                    // Record found, skipping save.
                                    success(recordName)
                                } else {
                                    // No record found, saving new record.
                                    guard let fileUrl = fileUrlBlock() else {
                                        Logger.error("\(self.logTag) error preparing file for upload.")
                                        failure(OWSErrorWithCodeDescription(.exportBackupError,
                                                                            NSLocalizedString("BACKUP_EXPORT_ERROR_SAVE_FILE_TO_CLOUD_FAILED",
                                                                                              comment: "Error indicating the a backup export failed to save a file to the cloud.")))
                                        return
                                    }

                                    saveFileToCloud(fileUrl: fileUrl,
                                                    recordName: recordName,
                                                    recordType: recordType,
                                                    success: success,
                                                    failure: failure)
                                }
        },
                            failure: failure)
    }

    private class func checkForFileInCloud(recordName: String,
                                          success: @escaping (CKRecord?) -> Swift.Void,
                                          failure: @escaping (Error) -> Swift.Void) {
        let recordId = CKRecordID(recordName: recordName)
        let fetchOperation = CKFetchRecordsOperation(recordIDs: [recordId ])
        // Don't download the file; we're just using the fetch to check whether or
        // not this record already exists.
        fetchOperation.desiredKeys = []
        fetchOperation.perRecordCompletionBlock = { (record, recordId, error) in
            if let error = error {
                if let ckerror = error as? CKError {
                    if ckerror.code == .unknownItem {
                        // Record not found.
                        success(nil)
                        return
                    }
                    Logger.error("\(self.logTag) error fetching record: \(error) \(ckerror.code).")
                } else {
                    Logger.error("\(self.logTag) error fetching record: \(error).")
                }
                failure(error)
                return
            }
            guard let record = record else {
                Logger.error("\(self.logTag) missing fetching record.")
                failure(OWSErrorWithCodeDescription(.exportBackupError,
                                                    NSLocalizedString("BACKUP_EXPORT_ERROR_SAVE_FILE_TO_CLOUD_FAILED",
                                                                      comment: "Error indicating the a backup export failed to save a file to the cloud.")))
                return
            }
            // Record found.
            success(record)
        }
        let myContainer = CKContainer.default()
        let privateDatabase = myContainer.privateCloudDatabase
        privateDatabase.add(fetchOperation)
    }

    @objc
    public class func checkForManifestInCloud(success: @escaping (Bool) -> Swift.Void,
                                              failure: @escaping (Error) -> Swift.Void) {

        checkForFileInCloud(recordName: manifestRecordName,
                            success: { (record) in
                                success(record != nil)
        },
                            failure: failure)
    }

    @objc
    public class func fetchAllRecordNames(success: @escaping ([String]) -> Swift.Void,
                                          failure: @escaping (Error) -> Swift.Void) {

        let query = CKQuery(recordType: signalBackupRecordType, predicate: NSPredicate(value: true))
        // Fetch the first page of results for this query.
        fetchAllRecordNamesStep(query: query,
                                previousRecordNames: [String](),
                                cursor: nil,
                                success: success,
                                failure: failure)
    }

    private class func fetchAllRecordNamesStep(query: CKQuery,
                                               previousRecordNames: [String],
                                               cursor: CKQueryCursor?,
                                               success: @escaping ([String]) -> Swift.Void,
                                               failure: @escaping (Error) -> Swift.Void) {

        var allRecordNames = previousRecordNames

        let  queryOperation = CKQueryOperation(query: query)
        // If this isn't the first page of results for this query, resume
        // where we left off.
        queryOperation.cursor = cursor
        // Don't download the file; we're just using the query to get a list of record names.
        queryOperation.desiredKeys = []
        queryOperation.recordFetchedBlock = { (record) in
            assert(record.recordID.recordName.count > 0)
            allRecordNames.append(record.recordID.recordName)
        }
        queryOperation.queryCompletionBlock = { (cursor, error) in
            if let error = error {
                Logger.error("\(self.logTag) error fetching all record names: \(error).")
                failure(error)
                return
            }
            if let cursor = cursor {
                Logger.verbose("\(self.logTag) fetching more record names \(allRecordNames.count).")
                // There are more pages of results, continue fetching.
                fetchAllRecordNamesStep(query: query,
                                        previousRecordNames: allRecordNames,
                                        cursor: cursor,
                                        success: success,
                                        failure: failure)
                return
            }
            Logger.info("\(self.logTag) fetched \(allRecordNames.count) record names.")
            success(allRecordNames)
        }

        let myContainer = CKContainer.default()
        let privateDatabase = myContainer.privateCloudDatabase
        privateDatabase.add(queryOperation)
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

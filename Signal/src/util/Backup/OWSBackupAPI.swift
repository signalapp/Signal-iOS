//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import CloudKit

// We don't worry about atomic writes.  Each backup export
// will diff against last successful backup.
//
// Note that all of our CloudKit records are immutable.
// "Persistent" records are only uploaded once.
// "Ephemeral" records are always uploaded to a new record name.
@objc public class OWSBackupAPI: NSObject {

    // If we change the record types, we need to ensure indices
    // are configured properly in the CloudKit dashboard.
    //
    // TODO: Change the record types when we ship to production.
    static let signalBackupRecordType = "signalBackup"
    static let manifestRecordName = "manifest"
    static let payloadKey = "payload"
    static let maxRetries = 5

    private class func recordIdForTest() -> String {
        return "test-\(NSUUID().uuidString)"
    }

    private class func database() -> CKDatabase {
        let myContainer = CKContainer.default()
        let privateDatabase = myContainer.privateCloudDatabase
        return privateDatabase
    }

    private class func invalidServiceResponseError() -> Error {
        return OWSErrorWithCodeDescription(.backupFailure,
                                           NSLocalizedString("BACKUP_EXPORT_ERROR_INVALID_CLOUDKIT_RESPONSE",
                                                             comment: "Error indicating that the app received an invalid response from CloudKit."))
    }

    // MARK: - Upload

    @objc
    public class func saveTestFileToCloud(fileUrl: URL,
                                          success: @escaping (String) -> Void,
                                          failure: @escaping (Error) -> Void) {
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
                                                       success: @escaping (String) -> Void,
                                                       failure: @escaping (Error) -> Void) {
        saveFileToCloud(fileUrl: fileUrl,
                        recordName: "ephemeralFile-\(NSUUID().uuidString)",
            recordType: signalBackupRecordType,
            success: success,
            failure: failure)
    }

    // "Persistent" files may be shared between backup export; they should only be saved
    // once.  For example, attachment files should only be uploaded once.  Subsequent
    // backups can reuse the same record.
    @objc
    public class func recordNameForPersistentFile(fileId: String) -> String {
        return "persistentFile-\(fileId)"
    }

    // "Persistent" files may be shared between backup export; they should only be saved
    // once.  For example, attachment files should only be uploaded once.  Subsequent
    // backups can reuse the same record.
    @objc
    public class func savePersistentFileOnceToCloud(fileId: String,
                                                    fileUrlBlock: @escaping () -> URL?,
                                                    success: @escaping (String) -> Void,
                                                    failure: @escaping (Error) -> Void) {
        saveFileOnceToCloud(recordName: recordNameForPersistentFile(fileId: fileId),
            recordType: signalBackupRecordType,
            fileUrlBlock: fileUrlBlock,
            success: success,
            failure: failure)
    }

    @objc
    public class func upsertManifestFileToCloud(fileUrl: URL,
                                                success: @escaping (String) -> Void,
                                                failure: @escaping (Error) -> Void) {
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
                                      success: @escaping (String) -> Void,
                                      failure: @escaping (Error) -> Void) {
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
                                        success: @escaping (String) -> Void,
                                        failure: @escaping (Error) -> Void) {
        saveRecordToCloud(record: record,
                          remainingRetries: maxRetries,
                          success: success,
                          failure: failure)
    }

    private class func saveRecordToCloud(record: CKRecord,
                                         remainingRetries: Int,
                                         success: @escaping (String) -> Void,
                                         failure: @escaping (Error) -> Void) {

        database().save(record) {
            (_, error) in

            let outcome = outcomeForCloudKitError(error: error,
                                                    remainingRetries: remainingRetries,
                                                    label: "Save Record")
            switch outcome {
            case .success:
                let recordName = record.recordID.recordName
                success(recordName)
            case .failureDoNotRetry(let outcomeError):
                failure(outcomeError)
            case .failureRetryAfterDelay(let retryDelay):
                DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + retryDelay, execute: {
                    saveRecordToCloud(record: record,
                                      remainingRetries: remainingRetries - 1,
                                      success: success,
                                      failure: failure)
                })
            case .failureRetryWithoutDelay:
                DispatchQueue.global().async {
                    saveRecordToCloud(record: record,
                                      remainingRetries: remainingRetries - 1,
                                      success: success,
                                      failure: failure)
                }
            case .unknownItem:
                owsFailDebug("unexpected CloudKit response.")
                failure(invalidServiceResponseError())
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
                                        success: @escaping (String) -> Void,
                                        failure: @escaping (Error) -> Void) {

        checkForFileInCloud(recordName: recordName,
                            remainingRetries: maxRetries,
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
                                          fileUrlBlock: @escaping () -> URL?,
                                          success: @escaping (String) -> Void,
                                          failure: @escaping (Error) -> Void) {

        checkForFileInCloud(recordName: recordName,
                            remainingRetries: maxRetries,
                            success: { (record) in
                                if record != nil {
                                    // Record found, skipping save.
                                    success(recordName)
                                } else {
                                    // No record found, saving new record.
                                    guard let fileUrl = fileUrlBlock() else {
                                        Logger.error("error preparing file for upload.")
                                        failure(OWSErrorWithCodeDescription(.exportBackupError,
                                                                            NSLocalizedString("BACKUP_EXPORT_ERROR_SAVE_FILE_TO_CLOUD_FAILED",
                                                                                              comment: "Error indicating the backup export failed to save a file to the cloud.")))
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

    // MARK: - Delete

    @objc
    public class func deleteRecordsFromCloud(recordNames: [String],
                                            success: @escaping () -> Void,
                                            failure: @escaping (Error) -> Void) {
        deleteRecordsFromCloud(recordNames: recordNames,
                              remainingRetries: maxRetries,
                              success: success,
                              failure: failure)
    }

    private class func deleteRecordsFromCloud(recordNames: [String],
                                             remainingRetries: Int,
                                             success: @escaping () -> Void,
                                             failure: @escaping (Error) -> Void) {

        let recordIDs = recordNames.map { CKRecordID(recordName: $0) }
        let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
        deleteOperation.modifyRecordsCompletionBlock = { (records, recordIds, error) in

            let outcome = outcomeForCloudKitError(error: error,
                                                  remainingRetries: remainingRetries,
                                                  label: "Delete Records")
            switch outcome {
            case .success:
                success()
            case .failureDoNotRetry(let outcomeError):
                failure(outcomeError)
            case .failureRetryAfterDelay(let retryDelay):
                DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + retryDelay, execute: {
                    deleteRecordsFromCloud(recordNames: recordNames,
                                        remainingRetries: remainingRetries - 1,
                                        success: success,
                                        failure: failure)
                })
            case .failureRetryWithoutDelay:
                DispatchQueue.global().async {
                    deleteRecordsFromCloud(recordNames: recordNames,
                                        remainingRetries: remainingRetries - 1,
                                        success: success,
                                        failure: failure)
                }
            case .unknownItem:
                owsFailDebug("unexpected CloudKit response.")
                failure(invalidServiceResponseError())
            }
        }
        database().add(deleteOperation)
    }

    // MARK: - Exists?

    private class func checkForFileInCloud(recordName: String,
                                           remainingRetries: Int,
                                           success: @escaping (CKRecord?) -> Void,
                                           failure: @escaping (Error) -> Void) {
        let recordId = CKRecordID(recordName: recordName)
        let fetchOperation = CKFetchRecordsOperation(recordIDs: [recordId ])
        // Don't download the file; we're just using the fetch to check whether or
        // not this record already exists.
        fetchOperation.desiredKeys = []
        fetchOperation.perRecordCompletionBlock = { (record, recordId, error) in

            let outcome = outcomeForCloudKitError(error: error,
                                                    remainingRetries: remainingRetries,
                                                    label: "Check for Record")
            switch outcome {
            case .success:
                guard let record = record else {
                    owsFailDebug("missing fetching record.")
                    failure(invalidServiceResponseError())
                    return
                }
                // Record found.
                success(record)
            case .failureDoNotRetry(let outcomeError):
                failure(outcomeError)
            case .failureRetryAfterDelay(let retryDelay):
                DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + retryDelay, execute: {
                    checkForFileInCloud(recordName: recordName,
                                        remainingRetries: remainingRetries - 1,
                                        success: success,
                                        failure: failure)
                })
            case .failureRetryWithoutDelay:
                DispatchQueue.global().async {
                    checkForFileInCloud(recordName: recordName,
                                        remainingRetries: remainingRetries - 1,
                                        success: success,
                                        failure: failure)
                }
            case .unknownItem:
                // Record not found.
                success(nil)
            }
        }
        database().add(fetchOperation)
    }

    @objc
    public class func checkForManifestInCloud(success: @escaping (Bool) -> Void,
                                              failure: @escaping (Error) -> Void) {

        checkForFileInCloud(recordName: manifestRecordName,
                            remainingRetries: maxRetries,
                            success: { (record) in
                                success(record != nil)
        },
                            failure: failure)
    }

    @objc
    public class func fetchAllRecordNames(success: @escaping ([String]) -> Void,
                                          failure: @escaping (Error) -> Void) {

        let query = CKQuery(recordType: signalBackupRecordType, predicate: NSPredicate(value: true))
        // Fetch the first page of results for this query.
        fetchAllRecordNamesStep(query: query,
                                previousRecordNames: [String](),
                                cursor: nil,
                                remainingRetries: maxRetries,
                                success: success,
                                failure: failure)
    }

    private class func fetchAllRecordNamesStep(query: CKQuery,
                                               previousRecordNames: [String],
                                               cursor: CKQueryCursor?,
                                               remainingRetries: Int,
                                               success: @escaping ([String]) -> Void,
                                               failure: @escaping (Error) -> Void) {

        var allRecordNames = previousRecordNames

        let queryOperation = CKQueryOperation(query: query)
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

            let outcome = outcomeForCloudKitError(error: error,
                                                    remainingRetries: remainingRetries,
                                                    label: "Fetch All Records")
            switch outcome {
            case .success:
                if let cursor = cursor {
                    Logger.verbose("fetching more record names \(allRecordNames.count).")
                    // There are more pages of results, continue fetching.
                    fetchAllRecordNamesStep(query: query,
                                            previousRecordNames: allRecordNames,
                                            cursor: cursor,
                                            remainingRetries: maxRetries,
                                            success: success,
                                            failure: failure)
                    return
                }
                Logger.info("fetched \(allRecordNames.count) record names.")
                success(allRecordNames)
            case .failureDoNotRetry(let outcomeError):
                failure(outcomeError)
            case .failureRetryAfterDelay(let retryDelay):
                DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + retryDelay, execute: {
                    fetchAllRecordNamesStep(query: query,
                                            previousRecordNames: allRecordNames,
                                            cursor: cursor,
                                            remainingRetries: remainingRetries - 1,
                                            success: success,
                                            failure: failure)
                })
            case .failureRetryWithoutDelay:
                DispatchQueue.global().async {
                    fetchAllRecordNamesStep(query: query,
                                            previousRecordNames: allRecordNames,
                                            cursor: cursor,
                                            remainingRetries: remainingRetries - 1,
                                            success: success,
                                            failure: failure)
                }
            case .unknownItem:
                owsFailDebug("unexpected CloudKit response.")
                failure(invalidServiceResponseError())
            }
        }
        database().add(queryOperation)
    }

    // MARK: - Download

    @objc
    public class func downloadManifestFromCloud(
        success: @escaping (Data) -> Void,
        failure: @escaping (Error) -> Void) {
        downloadDataFromCloud(recordName: manifestRecordName,
                              success: success,
                              failure: failure)
    }

    @objc
    public class func downloadDataFromCloud(recordName: String,
                                            success: @escaping (Data) -> Void,
                                            failure: @escaping (Error) -> Void) {

        downloadFromCloud(recordName: recordName,
                          remainingRetries: maxRetries,
                          success: { (asset) in
                            DispatchQueue.global().async {
                                do {
                                    let data = try Data(contentsOf: asset.fileURL)
                                    success(data)
                                } catch {
                                    Logger.error("couldn't load asset file: \(error).")
                                    failure(invalidServiceResponseError())
                                }
                            }
        },
                          failure: failure)
    }

    @objc
    public class func downloadFileFromCloud(recordName: String,
                                            toFileUrl: URL,
                                            success: @escaping () -> Void,
                                            failure: @escaping (Error) -> Void) {

        downloadFromCloud(recordName: recordName,
                          remainingRetries: maxRetries,
                          success: { (asset) in
                            DispatchQueue.global().async {
                                do {
                                    try FileManager.default.copyItem(at: asset.fileURL, to: toFileUrl)
                                    success()
                                } catch {
                                    Logger.error("couldn't copy asset file: \(error).")
                                    failure(invalidServiceResponseError())
                                }
                            }
        },
                          failure: failure)
    }

    // We return the CKAsset and not its fileUrl because
    // CloudKit offers no guarantees around how long it'll
    // keep around the underlying file.  Presumably we can
    // defer cleanup by maintaining a strong reference to
    // the asset.
    private class func downloadFromCloud(recordName: String,
                                         remainingRetries: Int,
                                         success: @escaping (CKAsset) -> Void,
                                         failure: @escaping (Error) -> Void) {

        let recordId = CKRecordID(recordName: recordName)
        let fetchOperation = CKFetchRecordsOperation(recordIDs: [recordId ])
        // Download all keys for this record.
        fetchOperation.perRecordCompletionBlock = { (record, recordId, error) in

            let outcome = outcomeForCloudKitError(error: error,
                                                    remainingRetries: remainingRetries,
                                                    label: "Download Record")
            switch outcome {
            case .success:
                guard let record = record else {
                    Logger.error("missing fetching record.")
                    failure(invalidServiceResponseError())
                    return
                }
                guard let asset = record[payloadKey] as? CKAsset else {
                    Logger.error("record missing payload.")
                    failure(invalidServiceResponseError())
                    return
                }
                success(asset)
            case .failureDoNotRetry(let outcomeError):
                failure(outcomeError)
            case .failureRetryAfterDelay(let retryDelay):
                DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + retryDelay, execute: {
                    downloadFromCloud(recordName: recordName,
                                      remainingRetries: remainingRetries - 1,
                                      success: success,
                                      failure: failure)
                })
            case .failureRetryWithoutDelay:
                DispatchQueue.global().async {
                    downloadFromCloud(recordName: recordName,
                                      remainingRetries: remainingRetries - 1,
                                      success: success,
                                      failure: failure)
                }
            case .unknownItem:
                Logger.error("missing fetching record.")
                failure(invalidServiceResponseError())
            }
        }
        database().add(fetchOperation)
    }

    // MARK: - Access

    @objc
    public class func checkCloudKitAccess(completion: @escaping (Bool) -> Void) {
        CKContainer.default().accountStatus(completionHandler: { (accountStatus, error) in
            DispatchQueue.main.async {
                switch accountStatus {
                case .couldNotDetermine:
                    Logger.error("could not determine CloudKit account status:\(String(describing: error)).")
                    OWSAlerts.showErrorAlert(message: NSLocalizedString("CLOUDKIT_STATUS_COULD_NOT_DETERMINE", comment: "Error indicating that the app could not determine that user's CloudKit account status"))
                    completion(false)
                case .noAccount:
                    Logger.error("no CloudKit account.")
                    OWSAlerts.showErrorAlert(message: NSLocalizedString("CLOUDKIT_STATUS_NO_ACCOUNT", comment: "Error indicating that user does not have an iCloud account."))
                    completion(false)
                case .restricted:
                    Logger.error("restricted CloudKit account.")
                    OWSAlerts.showErrorAlert(message: NSLocalizedString("CLOUDKIT_STATUS_RESTRICTED", comment: "Error indicating that the app was prevented from accessing the user's CloudKit account."))
                    completion(false)
                case .available:
                    completion(true)
                }
            }
        })
    }

    // MARK: - Retry

    private enum APIOutcome {
        case success
        case failureDoNotRetry(error:Error)
        case failureRetryAfterDelay(retryDelay: TimeInterval)
        case failureRetryWithoutDelay
        // This only applies to fetches.
        case unknownItem
    }

    private class func outcomeForCloudKitError(error: Error?,
                                                remainingRetries: Int,
                                                label: String) -> APIOutcome {
        if let error = error as? CKError {
            if error.code == CKError.unknownItem {
                // This is not always an error for our purposes.
                Logger.verbose("\(label) unknown item.")
                return .unknownItem
            }

            Logger.error("\(label) failed: \(error)")

            if remainingRetries < 1 {
                Logger.verbose("\(label) no more retries.")
                return .failureDoNotRetry(error:error)
            }

            if #available(iOS 11, *) {
                if error.code == CKError.serverResponseLost {
                    Logger.verbose("\(label) retry without delay.")
                    return .failureRetryWithoutDelay
                }
            }

            switch error {
            case CKError.requestRateLimited, CKError.serviceUnavailable, CKError.zoneBusy:
                let retryDelay = error.retryAfterSeconds ?? 3.0
                Logger.verbose("\(label) retry with delay: \(retryDelay).")
                return .failureRetryAfterDelay(retryDelay:retryDelay)
            case CKError.networkFailure:
                Logger.verbose("\(label) retry without delay.")
                return .failureRetryWithoutDelay
            default:
                Logger.verbose("\(label) unknown CKError.")
                return .failureDoNotRetry(error:error)
            }
        } else if let error = error {
            Logger.error("\(label) failed: \(error)")
            if remainingRetries < 1 {
                Logger.verbose("\(label) no more retries.")
                return .failureDoNotRetry(error:error)
            }
            Logger.verbose("\(label) unknown error.")
            return .failureDoNotRetry(error:error)
        } else {
            Logger.info("\(label) succeeded.")
            return .success
        }
    }
}

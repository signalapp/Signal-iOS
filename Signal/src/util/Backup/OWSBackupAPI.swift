//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import CloudKit
import PromiseKit

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
    static let manifestRecordNameSuffix = "manifest"
    static let payloadKey = "payload"
    static let maxRetries = 5

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
    public class func recordNameForTestFile(recipientId: String) -> String {
        return "\(recordNamePrefix(forRecipientId: recipientId))test-\(NSUUID().uuidString)"
    }

    // "Ephemeral" files are specific to this backup export and will always need to
    // be saved.  For example, a complete image of the database is exported each time.
    // We wouldn't want to overwrite previous images until the entire backup export is
    // complete.
    @objc
    public class func recordNameForEphemeralFile(recipientId: String,
                                                 label: String) -> String {
        return "\(recordNamePrefix(forRecipientId: recipientId))ephemeral-\(label)-\(NSUUID().uuidString)"
    }

    // "Persistent" files may be shared between backup export; they should only be saved
    // once.  For example, attachment files should only be uploaded once.  Subsequent
    // backups can reuse the same record.
    @objc
    public class func recordNameForPersistentFile(recipientId: String,
                                                  fileId: String) -> String {
        return "\(recordNamePrefix(forRecipientId: recipientId))persistentFile-\(fileId)"
    }

    // "Persistent" files may be shared between backup export; they should only be saved
    // once.  For example, attachment files should only be uploaded once.  Subsequent
    // backups can reuse the same record.
    @objc
    public class func recordNameForManifest(recipientId: String) -> String {
        return "\(recordNamePrefix(forRecipientId: recipientId))\(manifestRecordNameSuffix)"
    }

    private class func isManifest(recordName: String) -> Bool {
        return recordName.hasSuffix(manifestRecordNameSuffix)
    }

    private class func recordNamePrefix(forRecipientId recipientId: String) -> String {
        return "\(recipientId)-"
    }

    private class func recipientId(forRecordName recordName: String) -> String? {
        let recipientIds = self.recipientIds(forRecordNames: [recordName])
        guard let recipientId = recipientIds.first else {
            return nil
        }
        return recipientId
    }

    private static var recordNamePrefixRegex = {
        return try! NSRegularExpression(pattern: "^(\\+[0-9]+)\\-")
    }()

    private class func recipientIds(forRecordNames recordNames: [String]) -> [String] {
        var recipientIds = [String]()
        for recordName in recordNames {
            let regex = recordNamePrefixRegex
            guard let match: NSTextCheckingResult = regex.firstMatch(in: recordName, options: [], range: recordName.entireRange) else {
                Logger.warn("no match: \(recordName)")
                continue
            }
            guard match.numberOfRanges > 0 else {
                // Match must include first group.
                Logger.warn("invalid match: \(recordName)")
                continue
            }
            let firstRange = match.range(at: 1)
            guard firstRange.location == 0,
                firstRange.length > 0 else {
                    // Match must be at start of string and non-empty.
                    Logger.warn("invalid match: \(recordName) \(firstRange)")
                    continue
            }
            let recipientId = (recordName as NSString).substring(with: firstRange) as String
            recipientIds.append(recipientId)
        }
        return recipientIds
    }

    @objc
    public class func record(forFileUrl fileUrl: URL,
                             recordName: String) -> CKRecord {
        let recordType = signalBackupRecordType
        let recordID = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        let asset = CKAsset(fileURL: fileUrl)
        record[payloadKey] = asset

        return record
    }

    @objc
    public class func saveRecordsToCloudObjc(records: [CKRecord]) -> AnyPromise {
        return AnyPromise(saveRecordsToCloud(records: records))
    }

    public class func saveRecordsToCloud(records: [CKRecord]) -> Promise<Void> {

        // CloudKit's internal limit is 400, but I haven't found a constant for this.
        let kMaxBatchSize = 100
        return records.chunked(by: kMaxBatchSize).reduce(Promise.value(())) { (promise, batch) -> Promise<Void> in
            return promise.then(on: .global()) {
                saveRecordsToCloud(records: batch, remainingRetries: maxRetries)
                }.done {
                    Logger.verbose("Saved batch: \(batch.count)")
            }
        }
    }

    private class func saveRecordsToCloud(records: [CKRecord],
                                          remainingRetries: Int) -> Promise<Void> {

        let recordNames = records.map { (record) in
            return record.recordID.recordName
        }
        Logger.verbose("recordNames[\(recordNames.count)] \(recordNames[0..<10])...")

        return Promise { resolver in
            let saveOperation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            saveOperation.modifyRecordsCompletionBlock = { (savedRecords: [CKRecord]?, _, error) in

                let retry = {
                    // Only retry records which didn't already succeed.
                    var savedRecordNames = [String]()
                    if let savedRecords = savedRecords {
                        savedRecordNames = savedRecords.map { (record) in
                            return record.recordID.recordName
                        }
                    }
                    let retryRecords = records.filter({ (record) in
                        return !savedRecordNames.contains(record.recordID.recordName)
                    })

                    saveRecordsToCloud(records: retryRecords,
                                       remainingRetries: remainingRetries - 1)
                        .done { _ in
                            resolver.fulfill(())
                        }.catch { (error) in
                            resolver.reject(error)
                        }
                }

                let outcome = outcomeForCloudKitError(error: error,
                                                      remainingRetries: remainingRetries,
                                                      label: "Save Records[\(recordNames.count)]")
                switch outcome {
                case .success:
                    resolver.fulfill(())
                case .failureDoNotRetry(let outcomeError):
                    resolver.reject(outcomeError)
                case .failureRetryAfterDelay(let retryDelay):
                    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + retryDelay, execute: {
                        retry()
                    })
                case .failureRetryWithoutDelay:
                    DispatchQueue.global().async {
                        retry()
                    }
                case .unknownItem:
                    owsFailDebug("unexpected CloudKit response.")
                    resolver.reject(invalidServiceResponseError())
                }
            }
            saveOperation.isAtomic = false
            saveOperation.savePolicy = .allKeys

            // TODO: use perRecordProgressBlock and perRecordCompletionBlock.
//            open var perRecordProgressBlock: ((CKRecord, Double) -> Void)?
//            open var perRecordCompletionBlock: ((CKRecord, Error?) -> Void)?

            // These APIs are only available in iOS 9.3 and later.
            if #available(iOS 9.3, *) {
                saveOperation.isLongLived = true
                saveOperation.qualityOfService = .background
            }

            database().add(saveOperation)
        }
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

        let recordIDs = recordNames.map { CKRecord.ID(recordName: $0) }
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
                                           remainingRetries: Int) -> Promise<CKRecord?> {

        Logger.verbose("checkForFileInCloud \(recordName)")

        let (promise, resolver) = Promise<CKRecord?>.pending()

        let recordId = CKRecord.ID(recordName: recordName)
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
                    resolver.reject(invalidServiceResponseError())
                    return
                }
                // Record found.
                resolver.fulfill(record)
            case .failureDoNotRetry(let outcomeError):
                resolver.reject(outcomeError)
            case .failureRetryAfterDelay(let retryDelay):
                DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + retryDelay, execute: {
                    checkForFileInCloud(recordName: recordName,
                                        remainingRetries: remainingRetries - 1)
                        .done { (record) in
                            resolver.fulfill(record)
                        }.catch { (error) in
                            resolver.reject(error)
                        }
                })
            case .failureRetryWithoutDelay:
                DispatchQueue.global().async {
                    checkForFileInCloud(recordName: recordName,
                                        remainingRetries: remainingRetries - 1)
                        .done { (record) in
                            resolver.fulfill(record)
                        }.catch { (error) in
                            resolver.reject(error)
                        }
                }
            case .unknownItem:
                // Record not found.
                resolver.fulfill(nil)
            }
        }
        database().add(fetchOperation)
        return promise
    }

    @objc
    public class func checkForManifestInCloudObjc(recipientId: String) -> AnyPromise {
        return AnyPromise(checkForManifestInCloud(recipientId: recipientId))
    }

    public class func checkForManifestInCloud(recipientId: String) -> Promise<Bool> {

        let recordName = recordNameForManifest(recipientId: recipientId)
        return checkForFileInCloud(recordName: recordName,
                                   remainingRetries: maxRetries)
            .map { (record) in
                return record != nil
        }
    }

    @objc
    public class func allRecipientIdsWithManifestsInCloud(success: @escaping ([String]) -> Void,
                                                          failure: @escaping (Error) -> Void) {

        let processResults = { (recordNames: [String]) in
            DispatchQueue.global().async {
                let manifestRecordNames = recordNames.filter({ (recordName) -> Bool in
                    self.isManifest(recordName: recordName)
                })
                let recipientIds = self.recipientIds(forRecordNames: manifestRecordNames)
                success(recipientIds)
            }
        }

        let query = CKQuery(recordType: signalBackupRecordType, predicate: NSPredicate(value: true))
        // Fetch the first page of results for this query.
        fetchAllRecordNamesStep(recipientId: nil,
                                query: query,
                                previousRecordNames: [String](),
                                cursor: nil,
                                remainingRetries: maxRetries,
                                success: processResults,
                                failure: failure)
    }

    @objc
    public class func fetchAllRecordNames(recipientId: String,
                                          success: @escaping ([String]) -> Void,
                                          failure: @escaping (Error) -> Void) {

        let query = CKQuery(recordType: signalBackupRecordType, predicate: NSPredicate(value: true))
        // Fetch the first page of results for this query.
        fetchAllRecordNamesStep(recipientId: recipientId,
                                query: query,
                                previousRecordNames: [String](),
                                cursor: nil,
                                remainingRetries: maxRetries,
                                success: success,
                                failure: failure)
    }

    private class func fetchAllRecordNamesStep(recipientId: String?,
                                               query: CKQuery,
                                               previousRecordNames: [String],
                                               cursor: CKQueryOperation.Cursor?,
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

            let recordName = record.recordID.recordName

            if let recipientId = recipientId {
                let prefix = recordNamePrefix(forRecipientId: recipientId)
                guard recordName.hasPrefix(prefix) else {
                    Logger.info("Ignoring record: \(recordName)")
                    return
                }
            }

            allRecordNames.append(recordName)
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
                    fetchAllRecordNamesStep(recipientId: recipientId,
                                            query: query,
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
                    fetchAllRecordNamesStep(recipientId: recipientId,
                                            query: query,
                                            previousRecordNames: allRecordNames,
                                            cursor: cursor,
                                            remainingRetries: remainingRetries - 1,
                                            success: success,
                                            failure: failure)
                })
            case .failureRetryWithoutDelay:
                DispatchQueue.global().async {
                    fetchAllRecordNamesStep(recipientId: recipientId,
                                            query: query,
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
    public class func downloadManifestFromCloudObjc(recipientId: String) -> AnyPromise {
        return AnyPromise(downloadManifestFromCloud(recipientId: recipientId))
    }

    public class func downloadManifestFromCloud(recipientId: String) -> Promise<Data> {

        let recordName = recordNameForManifest(recipientId: recipientId)
        return downloadDataFromCloud(recordName: recordName)
    }

    @objc
    public class func downloadDataFromCloudObjc(recordName: String) -> AnyPromise {
        return AnyPromise(downloadDataFromCloud(recordName: recordName))
    }

    public class func downloadDataFromCloud(recordName: String) -> Promise<Data> {
        return downloadFromCloud(recordName: recordName,
                                 remainingRetries: maxRetries)
            .map { (asset) -> Data in
                guard let fileURL = asset.fileURL else {
                    throw invalidServiceResponseError()
                }
                return try Data(contentsOf: fileURL)
        }
    }

    @objc
    public class func downloadFileFromCloudObjc(recordName: String,
                                                toFileUrl: URL) -> AnyPromise {
        return AnyPromise(downloadFileFromCloud(recordName: recordName,
                                                toFileUrl: toFileUrl))
    }

    public class func downloadFileFromCloud(recordName: String,
                                            toFileUrl: URL) -> Promise<Void> {

        return downloadFromCloud(recordName: recordName,
                                 remainingRetries: maxRetries)
            .done { asset in
                guard let fileURL = asset.fileURL else {
                    throw invalidServiceResponseError()
                }
                try FileManager.default.copyItem(at: fileURL, to: toFileUrl)
        }
    }

    // We return the CKAsset and not its fileUrl because
    // CloudKit offers no guarantees around how long it'll
    // keep around the underlying file.  Presumably we can
    // defer cleanup by maintaining a strong reference to
    // the asset.
    private class func downloadFromCloud(recordName: String,
                                         remainingRetries: Int) -> Promise<CKAsset> {

        Logger.verbose("downloadFromCloud \(recordName)")

        let (promise, resolver) = Promise<CKAsset>.pending()

        let recordId = CKRecord.ID(recordName: recordName)
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
                    resolver.reject(invalidServiceResponseError())
                    return
                }
                guard let asset = record[payloadKey] as? CKAsset else {
                    Logger.error("record missing payload.")
                    resolver.reject(invalidServiceResponseError())
                    return
                }
                resolver.fulfill(asset)
            case .failureDoNotRetry(let outcomeError):
                resolver.reject(outcomeError)
            case .failureRetryAfterDelay(let retryDelay):
                DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + retryDelay, execute: {
                    downloadFromCloud(recordName: recordName,
                                      remainingRetries: remainingRetries - 1)
                        .done { (asset) in
                            resolver.fulfill(asset)
                        }.catch { (error) in
                            resolver.reject(error)
                        }
                })
            case .failureRetryWithoutDelay:
                DispatchQueue.global().async {
                    downloadFromCloud(recordName: recordName,
                                      remainingRetries: remainingRetries - 1)
                        .done { (asset) in
                            resolver.fulfill(asset)
                        }.catch { (error) in
                            resolver.reject(error)
                        }
                }
            case .unknownItem:
                Logger.error("missing fetching record.")
                resolver.reject(invalidServiceResponseError())
            }
        }
        database().add(fetchOperation)

        return promise
    }

    // MARK: - Access

    @objc public enum BackupError: Int, Error {
        case couldNotDetermineAccountStatus
        case noAccount
        case restrictedAccountStatus
    }

    @objc
    public class func ensureCloudKitAccessObjc() -> AnyPromise {
        return AnyPromise(ensureCloudKitAccess())
    }

    public class func ensureCloudKitAccess() -> Promise<Void> {
        let (promise, resolver) = Promise<Void>.pending()
        CKContainer.default().accountStatus { (accountStatus, error) in
            if let error = error {
                Logger.error("Unknown error: \(String(describing: error)).")
                resolver.reject(error)
                return
            }
            switch accountStatus {
            case .couldNotDetermine:
                Logger.error("could not determine CloudKit account status: \(String(describing: error)).")
                resolver.reject(BackupError.couldNotDetermineAccountStatus)
            case .noAccount:
                Logger.error("no CloudKit account.")
                resolver.reject(BackupError.noAccount)
            case .restricted:
                Logger.error("restricted CloudKit account.")
                resolver.reject(BackupError.restrictedAccountStatus)
            case .available:
                Logger.verbose("CloudKit access okay.")
                resolver.fulfill(())
            @unknown default:
                resolver.reject(OWSAssertionError("unknown CloudKit account status"))
            }
        }
        return promise
    }

    @objc
    public class func errorMessage(forCloudKitAccessError error: Error) -> String {
        if let backupError = error as? BackupError {
            Logger.error("Backup error: \(String(describing: backupError)).")
            switch backupError {
            case .couldNotDetermineAccountStatus:
                return NSLocalizedString("CLOUDKIT_STATUS_COULD_NOT_DETERMINE", comment: "Error indicating that the app could not determine that user's iCloud account status")
            case .noAccount:
                return NSLocalizedString("CLOUDKIT_STATUS_NO_ACCOUNT", comment: "Error indicating that user does not have an iCloud account.")
            case .restrictedAccountStatus:
                return NSLocalizedString("CLOUDKIT_STATUS_RESTRICTED", comment: "Error indicating that the app was prevented from accessing the user's iCloud account.")
            }
        } else {
            Logger.error("Unknown error: \(String(describing: error)).")
            return NSLocalizedString("CLOUDKIT_STATUS_COULD_NOT_DETERMINE", comment: "Error indicating that the app could not determine that user's iCloud account status")
        }
    }

    // MARK: - Retry

    private enum APIOutcome {
        case success
        case failureDoNotRetry(error: Error)
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

            if error.code == CKError.serverResponseLost {
                Logger.verbose("\(label) retry without delay.")
                return .failureRetryWithoutDelay
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

    // MARK: -

    @objc
    public class func setup() {
        cancelAllLongLivedOperations()
    }

    private class func cancelAllLongLivedOperations() {
        // These APIs are only available in iOS 9.3 and later.
        guard #available(iOS 9.3, *) else {
            return
        }

        let container = CKContainer.default()
        container.fetchAllLongLivedOperationIDs { (operationIds, error) in
            if let error = error {
                Logger.error("Could not get all long lived operations: \(error)")
                return
            }
            guard let operationIds = operationIds else {
                Logger.error("No operation ids.")
                return
            }

            for operationId in operationIds {
                container.fetchLongLivedOperation(withID: operationId, completionHandler: { (operation, error) in
                    if let error = error {
                        Logger.error("Could not get long lived operation [\(operationId)]: \(error)")
                        return
                    }
                    guard let operation = operation else {
                        Logger.error("No operation.")
                        return
                    }
                    operation.cancel()
                })
            }
        }
    }
}

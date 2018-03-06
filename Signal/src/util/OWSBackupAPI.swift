//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import CloudKit

//func FormatAnalyticsLocation(file: String, function: String) -> NSString {
//    return "\((file as NSString).lastPathComponent):\(function)" as NSString
//}
//
//func OWSProdError(_ eventName: String, file: String, function: String, line: Int32) {
//    let location = FormatAnalyticsLocation(file: file, function: function)
//    OWSAnalytics
//        .logEvent(eventName, severity: .error, parameters: nil, location: location.utf8String!, line:line)
//}
//
//func OWSProdInfo(_ eventName: String, file: String, function: String, line: Int32) {
//    let location = FormatAnalyticsLocation(file: file, function: function)
//    OWSAnalytics
//        .logEvent(eventName, severity: .info, parameters: nil, location: location.utf8String!, line:line)
//}

@objc public class OWSBackupAPI: NSObject {
    @objc
    public class func recordIdForTest() -> String {
        return "test-\(NSUUID().uuidString)"
    }

    @objc
    public class func recordIdForAttachmentStream(value: TSAttachmentStream) -> String {
        return "attachment-stream-\(value.uniqueId)"
    }

    @objc
    public class func saveTestFileToCloud(fileUrl: NSURL,
                                            completion: @escaping (Error?) -> Swift.Void) {
        saveFileToCloud(fileUrl: fileUrl,
                          recordId: recordIdForTest(),
                          recordType: "test",
            completion: completion)
    }

    @objc
    public class func saveFileToCloud(fileUrl: NSURL,
                                        recordId: String,
                                        recordType: String,
                                        completion: @escaping (Error?) -> Swift.Void) {
        let recordID = CKRecordID(recordName: recordId)
        let record = CKRecord(recordType: recordType, recordID: recordID)
//        artworkRecord["title"] = "MacKerricher State Park" as NSString
//        artworkRecord["artist"] = "Mei Chen" as NSString
//        artworkRecord["address"] = "Fort Bragg, CA" as NSString
//        artworkRecord[@"title" ] = @"MacKerricher State Park";
//        artworkRecord[@"artist"] = @"Mei Chen";
//        artworkRecord[@"address"] = @"Fort Bragg, CA";

        let myContainer = CKContainer.default()
        let privateDatabase = myContainer.privateCloudDatabase
        privateDatabase.save(record) {
            (record, error) in

            if let error = error {
                Logger.error("\(self.logTag) error saving record: \(error)")
                completion(error)
            } else {
                Logger.info("\(self.logTag) saved record.")
                completion(nil)
            }
        }
    }

    @objc
    public class func checkCloudKitAccess(completion: @escaping (Bool) -> Swift.Void) {
        CKContainer.default().accountStatus(completionHandler: { (accountStatus, error) in
            DispatchQueue.main.async {
            switch accountStatus {
            case .couldNotDetermine:
                Logger.error("\(self.logTag) could not determine CloudKit account status:\(error).")
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
                Logger.error("\(self.logTag) no CloudKit account.")
                completion(true)
            }
            }
        })
    }
}

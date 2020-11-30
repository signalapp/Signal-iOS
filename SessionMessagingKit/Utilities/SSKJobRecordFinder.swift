
@objc(SSKJobRecordFinder)
public class JobRecordFinder: NSObject, Finder {

    public typealias ExtensionType = YapDatabaseSecondaryIndex
    public typealias TransactionType = YapDatabaseSecondaryIndexTransaction

    public enum JobRecordField: String {
        case status, label, sortId
    }

    public func getNextReady(label: String, transaction: YapDatabaseReadTransaction) -> SSKJobRecord? {
        var result: SSKJobRecord?
        self.enumerateJobRecords(label: label, status: .ready, transaction: transaction) { jobRecord, stopPointer in
            result = jobRecord
            stopPointer.pointee = true
        }
        return result
    }

    public func allRecords(label: String, status: SSKJobRecordStatus, transaction: YapDatabaseReadTransaction) -> [SSKJobRecord] {
        var result: [SSKJobRecord] = []
        self.enumerateJobRecords(label: label, status: status, transaction: transaction) { jobRecord, _ in
            result.append(jobRecord)
        }
        return result
    }

    public func enumerateJobRecords(label: String, status: SSKJobRecordStatus, transaction: YapDatabaseReadTransaction, block: @escaping (SSKJobRecord, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let queryFormat = String(format: "WHERE %@ = ? AND %@ = ? ORDER BY %@", JobRecordField.status.rawValue, JobRecordField.label.rawValue, JobRecordField.sortId.rawValue)
        let query = YapDatabaseQuery(string: queryFormat, parameters: [status.rawValue, label])

        self.ext(transaction: transaction).enumerateKeysAndObjects(matching: query) { _, _, object, stopPointer in
            guard let jobRecord = object as? SSKJobRecord else {
                owsFailDebug("expecting jobRecord but found: \(object)")
                return
            }
            block(jobRecord, stopPointer)
        }
    }

    public static var dbExtensionName: String {
        return "SecondaryIndexJobRecord"
    }

    @objc
    public class func asyncRegisterDatabaseExtensionObjC(storage: OWSStorage) {
        asyncRegisterDatabaseExtension(storage: storage)
    }

    public static var dbExtensionConfig: YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(JobRecordField.sortId.rawValue, with: .integer)
        setup.addColumn(JobRecordField.status.rawValue, with: .integer)
        setup.addColumn(JobRecordField.label.rawValue, with: .text)

        let block: YapDatabaseSecondaryIndexWithObjectBlock = { transaction, dict, collection, key, object in
            guard let jobRecord = object as? SSKJobRecord else {
                return
            }

            dict[JobRecordField.sortId.rawValue] = jobRecord.sortId
            dict[JobRecordField.status.rawValue] = jobRecord.status.rawValue
            dict[JobRecordField.label.rawValue] = jobRecord.label
        }

        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock(block)

        let options = YapDatabaseSecondaryIndexOptions()
        let whitelist = YapWhitelistBlacklist(whitelist: Set([SSKJobRecord.collection()]))
        options.allowedCollections = whitelist

        return YapDatabaseSecondaryIndex.init(setup: setup, handler: handler, versionTag: "2", options: options)
    }
}

protocol Finder {
    associatedtype ExtensionType: YapDatabaseExtension
    associatedtype TransactionType: YapDatabaseExtensionTransaction

    static var dbExtensionName: String { get }
    static var dbExtensionConfig: ExtensionType { get }

    func ext(transaction: YapDatabaseReadTransaction) -> TransactionType

    static func asyncRegisterDatabaseExtension(storage: OWSStorage)
    static func testingOnly_ensureDatabaseExtensionRegistered(storage: OWSStorage)
}

extension Finder {

    public func ext(transaction: YapDatabaseReadTransaction) -> TransactionType {
        return transaction.ext(type(of: self).dbExtensionName) as! TransactionType
    }

    public static func asyncRegisterDatabaseExtension(storage: OWSStorage) {
        storage.asyncRegister(dbExtensionConfig, withName: dbExtensionName)
    }

    // Only for testing.
    public static func testingOnly_ensureDatabaseExtensionRegistered(storage: OWSStorage) {
        guard storage.registeredExtension(dbExtensionName) == nil else {
            return
        }

        storage.register(dbExtensionConfig, withName: dbExtensionName)
    }
}

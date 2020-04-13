//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol YAPDBSignalServiceAddressIndexable: class {
    var indexableUUIDValue: String? { get }
    var indexablePhoneNumberValue: String? { get }
}

extension SignalAccount: YAPDBSignalServiceAddressIndexable {
    var indexableUUIDValue: String? { return recipientUUID }
    var indexablePhoneNumberValue: String? { return recipientPhoneNumber }
}

extension SignalRecipient: YAPDBSignalServiceAddressIndexable {
    var indexableUUIDValue: String? { return recipientUUID }
    var indexablePhoneNumberValue: String? { return recipientPhoneNumber }
}

extension TSContactThread: YAPDBSignalServiceAddressIndexable {
    var indexableUUIDValue: String? { return contactUUID }
    var indexablePhoneNumberValue: String? { return contactPhoneNumber }
}

extension OWSUserProfile: YAPDBSignalServiceAddressIndexable {
    var indexableUUIDValue: String? { return recipientUUID }
    var indexablePhoneNumberValue: String? { return recipientPhoneNumber }
}

@objc
class YAPDBSignalServiceAddressIndex: NSObject {
    private static let indexableTypes: [YAPDBSignalServiceAddressIndexable.Type] = [
        SignalAccount.self,
        SignalRecipient.self,
        TSContactThread.self
    ]

    private static let uuidKey = "uuidKey"
    private static let phoneNumberKey = "phoneNumberKey"
    private static let classNameKey = "classNameKey"

    private static let phoneNumberIndexName = "index_on_recipientPhoneNumber"
    private static let uuidIndexName = "index_on_recipientUUID"

    func fetchOne<T: YAPDBSignalServiceAddressIndexable>(for address: SignalServiceAddress, transaction: YapDatabaseReadTransaction) -> T? {
        if let result: T = fetchOneForUUID(address.uuid, transaction: transaction) {
            return result
        } else if let result: T = fetchOneForPhoneNumber(address.phoneNumber, transaction: transaction) {
            return result
        } else {
            return nil
        }
    }

    func fetchOneForUUID<T: YAPDBSignalServiceAddressIndexable>(_ uuid: UUID?, transaction: YapDatabaseReadTransaction) -> T? {
        guard let uuidString = uuid?.uuidString else { return nil }

        guard let ext = transaction.ext(YAPDBSignalServiceAddressIndex.uuidIndexName) as? YapDatabaseSecondaryIndexTransaction else {
            owsFailDebug("Unexpected transaction type for extension")
            return nil
        }

        let queryFormat = String(
            format: "WHERE %@ = \"%@\" AND %@ = \"%@\"",
            YAPDBSignalServiceAddressIndex.uuidKey,
            uuidString,
            YAPDBSignalServiceAddressIndex.classNameKey,
            NSStringFromClass(T.self)
        )
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        var matchedAccount: T?

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stop in
            guard let account = object as? T else {
                return
            }
            matchedAccount = account
            stop.pointee = true
        }

        return matchedAccount
    }

    func fetchOneForPhoneNumber<T: YAPDBSignalServiceAddressIndexable>(_ phoneNumber: String?, transaction: YapDatabaseReadTransaction) -> T? {
        guard let phoneNumber = phoneNumber else { return nil }

        guard let ext = transaction.ext(YAPDBSignalServiceAddressIndex.phoneNumberIndexName) as? YapDatabaseSecondaryIndexTransaction else {
            owsFailDebug("Unexpected transaction type for extension")
            return nil
        }

        let queryFormat = String(
            format: "WHERE %@ = \"%@\" AND %@ = \"%@\"",
            YAPDBSignalServiceAddressIndex.phoneNumberKey,
            phoneNumber,
            YAPDBSignalServiceAddressIndex.classNameKey,
            NSStringFromClass(T.self)
        )
        let query = YapDatabaseQuery(string: queryFormat, parameters: [])

        var matchedAccount: T?

        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stop in
            guard let account = object as? T else {
                return
            }
            matchedAccount = account
            stop.pointee = true
        }

        return matchedAccount
    }

    @objc
    static func asyncRegisterDatabaseExtensions(_ storage: OWSStorage) {
        storage.asyncRegister(indexUUIDExtension(), withName: uuidIndexName)
        storage.asyncRegister(indexPhoneNumberExtension(), withName: phoneNumberIndexName)
    }

    private static func indexUUIDExtension() -> YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(uuidKey, with: .text)
        setup.addColumn(classNameKey, with: .text)

        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock { _, dict, _, _, object in
            guard let indexableObject = object as? YAPDBSignalServiceAddressIndexable else {
                return
            }

            dict[uuidKey] = indexableObject.indexableUUIDValue
            dict[classNameKey] = NSStringFromClass(type(of: indexableObject))
        }

        return YapDatabaseSecondaryIndex(setup: setup, handler: handler, versionTag: "2")
    }

    private static func indexPhoneNumberExtension() -> YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(phoneNumberKey, with: .text)
        setup.addColumn(classNameKey, with: .text)

        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock { _, dict, _, _, object in
            guard let indexableObject = object as? YAPDBSignalServiceAddressIndexable else {
                return
            }

            dict[phoneNumberKey] = indexableObject.indexablePhoneNumberValue
            dict[classNameKey] = NSStringFromClass(type(of: indexableObject))
        }

        return YapDatabaseSecondaryIndex(setup: setup, handler: handler, versionTag: "2")
    }
}

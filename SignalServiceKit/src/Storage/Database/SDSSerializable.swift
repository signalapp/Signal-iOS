//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

func convertDateForGrdb(_ value: Date) -> Double {
    return value.timeIntervalSince1970
}

// MARK: - SDSSerializer

public protocol SDSSerializer {
    func asRecord() throws -> SDSRecord
}

// MARK: - SDSSerializer Helpers

public extension SDSSerializer {

    // MARK: - Numeric Primitive

    func archiveOptionalNSNumber<T>(_ value: NSNumber?, conversion: (NSNumber) -> T) -> T? {
        guard let value = value else {
            return nil
        }
        return conversion(value)
    }

    func archiveNSNumber<T>(_ value: NSNumber, conversion: (NSNumber) -> T) -> T {
        return conversion(value)
    }

    // MARK: - Date

    func archiveOptionalDate(_ value: Date?) -> Double? {
        guard let value = value else {
            return nil
        }
        return archiveDate(value)
    }

    func archiveDate(_ value: Date) -> Double {
        return convertDateForGrdb(value)
    }

    // MARK: - Blob

    func optionalArchive<T: SDSSwiftSerializable>(_ value: T?) -> Data? {
        guard let value = value else {
            return nil
        }
        return requiredArchive(value)
    }

    func requiredArchive<T: SDSSwiftSerializable>(_ value: T) -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            // owsFail() to match NSKeyedArchiver behavior (it throws an ObjC exception)
            owsFail("Failed to deserialize \(T.self): \(error)")
        }
    }

    func optionalArchive(_ value: Any?) -> Data? {
        guard let value = value else {
            return nil
        }
        return requiredArchive(value)
    }

    func requiredArchive(_ value: Any) -> Data {
        return try! NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false)
    }
}

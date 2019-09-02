//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import SignalCoreKit

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
        return value.timeIntervalSince1970
    }

    // MARK: - Blob

    func optionalArchive(_ value: Any?) -> Data? {
        guard let value = value else {
            return nil
        }
        return requiredArchive(value)
    }

    func requiredArchive(_ value: Any) -> Data {
        return NSKeyedArchiver.archivedData(withRootObject: value)
    }

    // MARK: - Safe Numerics

    func serializationSafeUInt(_ value: UInt) -> UInt {
        guard UInt.max > Int64.max else {
            return value
        }
        guard value < Int64.max else {
            if !CurrentAppContext().isRunningTests {
                owsFailDebug("Invalid value: \(value)")
            }
            return UInt(Int64.max)
        }
        return value
    }

    func serializationSafeUInt64(_ value: UInt64) -> UInt64 {
        guard value < Int64.max else {
            if !CurrentAppContext().isRunningTests {
                owsFailDebug("Invalid value: \(value)")
            }
            return UInt64(Int64.max)
        }
        return value
    }
}

//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
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
}

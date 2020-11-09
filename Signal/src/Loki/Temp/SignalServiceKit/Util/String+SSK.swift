//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension String {
    public var digitsOnly: String {
        return (self as NSString).digitsOnly()
    }

    func rtlSafeAppend(_ string: String) -> String {
        return (self as NSString).rtlSafeAppend(string)
    }

    public func substring(from index: Int) -> String {
        return String(self[self.index(self.startIndex, offsetBy: index)...])
    }

    public func substring(to index: Int) -> String {
        return String(prefix(index))
    }

    enum StringError: Error {
        case invalidCharacterShift
    }
}

// MARK: - Selector Encoding

private let selectorOffset: UInt32 = 17

public extension String {

    public func caesar(shift: UInt32) throws -> String {
        let shiftedScalars: [UnicodeScalar] = try unicodeScalars.map { c in
            guard let shiftedScalar = UnicodeScalar((c.value + shift) % 127) else {
                owsFailDebug("invalidCharacterShift")
                throw StringError.invalidCharacterShift
            }
            return shiftedScalar
        }
        return String(String.UnicodeScalarView(shiftedScalars))
    }

    public var encodedForSelector: String? {
        guard let shifted = try? self.caesar(shift: selectorOffset) else {
            owsFailDebug("shifted was unexpectedly nil")
            return nil
        }

        guard let data = shifted.data(using: .utf8) else {
            owsFailDebug("data was unexpectedly nil")
            return nil
        }

        return data.base64EncodedString()
    }

    public var decodedForSelector: String? {
        guard let data = Data(base64Encoded: self) else {
            owsFailDebug("data was unexpectedly nil")
            return nil
        }

        guard let shifted = String(data: data, encoding: .utf8) else {
            owsFailDebug("shifted was unexpectedly nil")
            return nil
        }

        return try? shifted.caesar(shift: 127 - selectorOffset)
    }
}

public extension NSString {

    @objc
    public var encodedForSelector: String? {
        return (self as String).encodedForSelector
    }

    @objc
    public var decodedForSelector: String? {
        return (self as String).decodedForSelector
    }
}

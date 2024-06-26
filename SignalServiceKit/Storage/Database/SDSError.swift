//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public struct SDSError: Error, CustomStringConvertible {
    private let descriptor: StaticString
    private let file: StaticString
    private let function: StaticString
    private let line: UInt

    private init(descriptor: StaticString, file: StaticString, function: StaticString, line: UInt) {
        self.descriptor = descriptor
        self.file = file
        self.function = function
        self.line = line
    }

    public var description: String {
        return "SDSError: \(descriptor) at \(file)#\(function):\(line)"
    }

    // MARK: -

    public static func missingRequiredField(
        _ file: StaticString = #file,
        _ function: StaticString = #function,
        _ line: UInt = #line
    ) -> SDSError {
        return SDSError(descriptor: #function, file: file, function: function, line: line)
    }

    public static func unexpectedType(
        _ file: StaticString = #file,
        _ function: StaticString = #function,
        _ line: UInt = #line
    ) -> SDSError {
        return SDSError(descriptor: #function, file: file, function: function, line: line)
    }

    public static func invalidResult(
        _ file: StaticString = #file,
        _ function: StaticString = #function,
        _ line: UInt = #line
    ) -> SDSError {
        return SDSError(descriptor: #function, file: file, function: function, line: line)
    }

    public static func invalidValue(
        _ file: StaticString = #file,
        _ function: StaticString = #function,
        _ line: UInt = #line
    ) -> SDSError {
        return SDSError(descriptor: #function, file: file, function: function, line: line)
    }

    public static func invalidTransaction(
        _ file: StaticString = #file,
        _ function: StaticString = #function,
        _ line: UInt = #line
    ) -> SDSError {
        return SDSError(descriptor: #function, file: file, function: function, line: line)
    }
}

//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public struct SDSError: Error, CustomStringConvertible {
    private let descriptor: String
    private let file: StaticString
    private let function: StaticString
    private let line: UInt

    public var description: String {
        return "SDSError: \(descriptor) at \(file)#\(function):\(line)"
    }

    // MARK: -

    public static func missingRequiredField(
        fieldName: String? = nil,
        _ file: StaticString = #file,
        _ function: StaticString = #function,
        _ line: UInt = #line,
    ) -> SDSError {
        return SDSError(descriptor: "\(#function): \(fieldName ?? "unspecified")", file: file, function: function, line: line)
    }

    public static func unexpectedType(
        _ file: StaticString = #file,
        _ function: StaticString = #function,
        _ line: UInt = #line,
    ) -> SDSError {
        return SDSError(descriptor: #function, file: file, function: function, line: line)
    }

    public static func invalidResult(
        _ file: StaticString = #file,
        _ function: StaticString = #function,
        _ line: UInt = #line,
    ) -> SDSError {
        return SDSError(descriptor: #function, file: file, function: function, line: line)
    }

    public static func invalidValue(
        _ file: StaticString = #file,
        _ function: StaticString = #function,
        _ line: UInt = #line,
    ) -> SDSError {
        return SDSError(descriptor: #function, file: file, function: function, line: line)
    }

    public static func invalidTransaction(
        _ file: StaticString = #file,
        _ function: StaticString = #function,
        _ line: UInt = #line,
    ) -> SDSError {
        return SDSError(descriptor: #function, file: file, function: function, line: line)
    }
}

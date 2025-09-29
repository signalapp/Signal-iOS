//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct OWSAssertionError: Error {
    #if TESTABLE_BUILD
    public static var test_skipAssertions = false
    #endif

    public let description: String
    public init(
        _ description: String,
        logger: PrefixedLogger = .empty(),
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        #if TESTABLE_BUILD
        if Self.test_skipAssertions {
            logger.warn("assertionError: \(description)")
        } else {
            owsFailDebug("assertionError: \(description)", logger: logger, file: file, function: function, line: line)
        }
        #else
        owsFailDebug("assertionError: \(description)", logger: logger, file: file, function: function, line: line)
        #endif
        self.description = description
    }
}

// An error that won't assert.
public struct OWSGenericError: Error {
    public let description: String
    public init(_ description: String) {
        self.description = description
    }
}

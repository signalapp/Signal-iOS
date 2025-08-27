//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct DarwinNotificationName: ExpressibleByStringLiteral {
    static let primaryDBFolderNameDidChange: DarwinNotificationName = "org.signal.primaryDBFolderNameDidChange"

    static func sdsCrossProcess(for type: AppContextType) -> DarwinNotificationName {
        DarwinNotificationName("org.signal.sdscrossprocess.\(type)")
    }

    static func connectionLock(for priority: Int) -> DarwinNotificationName {
        return DarwinNotificationName("org.signal.connection.\(priority)")
    }

    public typealias StringLiteralType = String

    public let rawValue: String

    public init(stringLiteral name: String) {
        owsPrecondition(!name.isEmpty)
        self.rawValue = name
    }

    public init(_ name: String) {
        owsAssertDebug(!name.isEmpty)
        self.rawValue = name
    }
}

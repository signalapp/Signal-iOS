//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct DarwinNotificationName: ExpressibleByStringLiteral {
    public static let nseDidReceiveNotification: DarwinNotificationName = "org.signal.nseDidReceiveNotification"
    public static let mainAppHandledNotification: DarwinNotificationName = "org.signal.mainAppHandledNotification"
    public static let mainAppLaunched: DarwinNotificationName = "org.signal.mainAppLaunched"
    public static let primaryDBFolderNameDidChange: DarwinNotificationName = "org.signal.primaryDBFolderNameDidChange"

    public static func sdsCrossProcess(for type: AppContextType) -> DarwinNotificationName {
        DarwinNotificationName("org.signal.sdscrossprocess.\(type)")
    }

    public typealias StringLiteralType = String

    private let stringValue: String

    public var isValid: Bool { !stringValue.isEmpty }

    public init(stringLiteral value: String) {
        stringValue = value
    }

    public init(_ name: String) {
        stringValue = name
    }

    public func withCString<T>(_ body: (UnsafePointer<CChar>) throws -> T) rethrows -> T {
        try stringValue.withCString(body)
    }
}

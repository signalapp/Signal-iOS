//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class DarwinNotificationName: NSObject, ExpressibleByStringLiteral {
    @objc
    public static let sdsCrossProcess: DarwinNotificationName = "org.signal.sdscrossprocess"
    @objc
    public static let nseDidReceiveNotification: DarwinNotificationName = "org.signal.nseDidReceiveNotification"
    @objc
    public static let mainAppHandledNotification: DarwinNotificationName = "org.signal.mainAppHandledNotification"
    @objc
    public static let mainAppLaunched: DarwinNotificationName = "org.signal.mainAppLaunched"

    public typealias StringLiteralType = String

    private let stringValue: String

    @objc
    public var cString: UnsafePointer<Int8> {
        return stringValue.withCString { $0 }
    }

    @objc
    public var isValid: Bool {
        return stringValue.isEmpty == false
    }

    public required init(stringLiteral value: String) {
        stringValue = value
    }

    @objc
    public init(_ name: String) {
        stringValue = name
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let otherName = object as? DarwinNotificationName else { return false }
        return otherName.stringValue == stringValue
    }

    public override var hash: Int {
        return stringValue.hashValue
    }
}

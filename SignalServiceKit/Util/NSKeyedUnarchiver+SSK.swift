//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension NSKeyedUnarchiver {
#if TESTABLE_BUILD
    public static func unarchivedObject<DecodedObjectType>(
        ofClass cls: DecodedObjectType.Type,
        from data: Data,
        requiringSecureCoding: Bool
    ) throws -> DecodedObjectType? where DecodedObjectType: NSObject, DecodedObjectType: NSCoding {
        let coder = try NSKeyedUnarchiver(forReadingFrom: data)
        coder.requiresSecureCoding = requiringSecureCoding
        return try coder.decodeTopLevelObject(of: cls, forKey: NSKeyedArchiveRootObjectKey)
    }
#endif
}

//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import ObjectiveC

public enum ObjectRetainer {
    private static var retainedObjectKey: UInt8 = 0

    /// Occasionally, there's an object (the `retainingObject`) that weakly
    /// references another object (the `retainedObject`), but there's nothing
    /// else retaining the latter. *Something* must retain the latter, though,
    /// and this method can accomplish that. It's most useful when working with
    /// older delegate-based Apple APIs, and there's better ways to avoid it
    /// when you control the implementations of both objects.
    ///
    /// Note: The `retainedObject` MUST NOT retain the `retainingObject`, either
    /// directly or indirectly.
    public static func retainObject(_ retainedObject: AnyObject, forLifetimeOf retainingObject: AnyObject) {
        objc_setAssociatedObject(
            retainingObject,
            &Self.retainedObjectKey,
            retainedObject,
            objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN,
        )
    }
}

//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension Sequence {

    /// Builds a dicitonary mapping the elements of a sequence to the value returned from `valueBuilder`
    /// The elements of a dictionary must be unique.
    func dictionaryMappingToValues<Value>(_ valueBuilder: ((Element) throws -> Value)) rethrows -> [Element: Value] {
        let kvPairs = try map { key in
            return (key, try valueBuilder(key))
        }
        return Dictionary(kvPairs) { (val1, _) -> Value in
            owsFailDebug("Key uniqueness conflict")
            return val1
        }
    }
}

//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension Sequence {

    /// Builds a dicitonary mapping the elements of a sequence to the value returned from `valueBuilder`
    /// The elements of a dictionary must be unique.
    func dictionaryMappingToValues<Value>(_ valueBuilder: ((Element) -> Value)) -> [Element: Value] {
        let kvPairs = map { key in
            return (key, valueBuilder(key))
        }
        return Dictionary(kvPairs) { (val1, _) -> Value in
            owsFailDebug("Key uniqueness conflict")
            return val1
        }
    }
}

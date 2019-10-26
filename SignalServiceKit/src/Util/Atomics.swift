//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class AtomicBool: NSObject {
    private var value: Bool

    @objc
    public required init(_ value: Bool) {
        self.value = value
    }

    // All instances can share a single queue.
    private static let serialQueue = DispatchQueue(label: "AtomicBool")

    @objc
    public func get() -> Bool {
        return AtomicBool.serialQueue.sync {
            return self.value
        }
    }

    @objc
    public func set(_ value: Bool) {
        return AtomicBool.serialQueue.sync {
            self.value = value
        }
    }
}

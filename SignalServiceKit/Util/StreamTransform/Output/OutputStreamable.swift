//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Simple protocol for writing chunks of data. This is effectively a protocol
/// wrapper around OutputStream, but allows for easier testing and
/// proxying of the OutputStream class itself.
public protocol OutputStreamable: Streamable {
    func write(data: Data) throws
}

extension OutputStream: OutputStreamable {
    public func write(data: Data) throws {
        let writeLen = data.withUnsafeBytes {
            guard let bytes = $0.baseAddress?.assumingMemoryBound(to: Int8.self) else {
                return 0
            }
            return self.write(bytes, maxLength: data.count)
        }
        if writeLen != data.count {
            owsFailDebug("The amount written doesn't match amount that was attempted.")
        }
    }
}

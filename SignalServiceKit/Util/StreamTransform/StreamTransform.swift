//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// An stream transform allows transforming an stream of data and returns
/// the the transformed data to be further processed by other transforms.
/// StreamTransforms should support chaining to and from other
/// transforms. (e.g. encrypt and compress a stream)
public protocol StreamTransform {

    /// Transform the passed in data. It is worth noting that the length of the data is not
    /// guaranteed to match the input data, and it shouldn't be assumed that passing
    /// data into the transform will result in any data being returned (In these cases,
    /// the returned Data object will be empty)
    func transform(data: Data) throws -> Data

    /// Returns `true` if the transform has pending bytes buffered.
    var hasPendingBytes: Bool { get }
}

public extension StreamTransform {
    var hasPendingBytes: Bool { return false }
}

public protocol BufferedStreamTransform {
    /// Returns data buffered by the transform.  Depending on internal implementations
    /// this may return all or just part of the buffered data.  Callers can consult
    /// `hasPendingBytes` to determing if this call should be expected to return data.
    func readBufferedData() throws -> Data
}

public protocol FinalizableStreamTransform {

    /// Flush any remaining data transform and/or generate any necessary footer data
    /// Calling this is required before closing the stream.
    /// Note that `hasPendingBytes` may still return true after `finalize()` has
    /// been called if `finalize()` results in a buffer of data to be returned to the caller.
    func finalize() throws -> Data

    /// Returns if `finalize()` has been called on the current transform
    var hasFinalized: Bool { get }
}

/// Read any available bytes remaining in the list of transforms including
/// any buffered data or pending footer data.
/// 
/// Do this by starting with an empty data buffer, and walking through
/// each transform:
/// 1. If there is data from the prior transform in the chain, transform
///    the data and pass to the next transform.
/// 2. If the prior transform didn't return data, and the current transform
///    has pending bytes, read that pending data and pass to the next transform.
/// 3. Finally, if the transform doesn't have any pending bytes, attempt to
///    finalize the transform and return any data from the operation to
///    the next transform in the chain.
/// 4. Because there are situations where there may be pending data
///    (hasPendingBytes == true) _after_ finalization, transforms may
///    move from step (3) back to step (2) while any final bytes are
///    cleared out.
///
/// Once all transforms have moved through all the above states,
/// `hasBytesAvailable` should return `false` and callers should
/// stop reading.
public extension Array where Element == any StreamTransform {
    func readNextRemainingBytes() throws -> Data {
        return try self.reduce(Data()) { pendingResult, transform in
            if pendingResult.count > 0 {
                if
                    let finalizableTransform = transform as? FinalizableStreamTransform,
                    finalizableTransform.hasFinalized
                {
                    owsFailDebug("Can't pass data to a finalized transform")
                }
                // Still data coming through the pipeline, process it and return.
                return try transform.transform(data: pendingResult)
            }
            // There are still bytes on the current transform, so return those
            // This could be before or after the transform has finalized.
            if
                transform.hasPendingBytes,
                let bufferedStreamTransform = transform as? BufferedStreamTransform
            {
                let data = try bufferedStreamTransform.readBufferedData()
                if data.count > 0 {
                    return data
                }
            }
            if
                let finalizableTransform = transform as? FinalizableStreamTransform,
                !finalizableTransform.hasFinalized
            {
                // Exhaused all bytes currently in the transform, time to finalize.
                return try finalizableTransform.finalize()
            }
            // All done with this transform, return empty.
            return Data()
        }
    }
}

//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// An stream transform allows transforming an input stream of data and returns
/// the results to be further processed.
/// StreamTransforms should support chaining to and from other
/// transforms. (e.g. encrypt and compress a stream)
public protocol StreamTransform {

    /// Initialize the transform and generate any necessary header data required before body writing begins
    func initializeAndReturnHeaderData() throws -> Data

    /// Transform the input data to be passed to the output stream.  It is worth noting
    /// that the length of the data is not guaranteed to match the input data, and
    /// it shouldn't be assumed that passing data into the transform will result in
    /// any data being returned (In these cases, the returned Data object will be empty)
    func transform(data: Data) throws -> Data

    /// Flush any remaining data and/or write any necessary footer data
    /// required before closing the stream
    func finalizeAndReturnFooterData() throws -> Data
}

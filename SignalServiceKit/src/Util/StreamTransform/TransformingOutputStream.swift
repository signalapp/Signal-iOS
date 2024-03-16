//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Simple wrapper around an OutputStream that allows adding as an
/// output endpoint for OutputTransform chains
public final class TransformingOutputStream: OutputStreamable {

    private let transforms: [any StreamTransform]
    private let outputStream: OutputStreamable
    private let runLoop: RunLoop?

    private var hasInitialized: Bool = false

    public init(
        transforms: [any StreamTransform],
        outputStream: OutputStreamable,
        runLoop: RunLoop? = nil
    ) {
        self.transforms = transforms
        self.outputStream = outputStream
        self.runLoop = runLoop
    }

    /// Iterates through each transform, initializing transforms and allowing it to generate
    /// one-time headers required by the internal transform implementation.
    public func initializeAndWriteHeader() throws {
        // The tricky part is the 'inner' transforms need to pass their generated
        // header to the next transform in the chain to transform is as part of it's regular body data.
        //
        // For each transform in the list, do the following:
        // 1. Generate the header for this transform.  Generated first in case there's any hidden
        //    initialization that happens during header generation and needs to be called before transform.
        // 2. Iterate over any previously generated header data and transform those values with the current transform.
        // 3. Append the header data generated in (1) and return.
        //
        // After this loop, reverse the list and write each header to the output stream. This results in the
        // last 'outermost' transform having it's header first in the output stream, followed in decreasing
        // order to the 'innermost' transform.
        let transformDatas = try transforms.reduce([Data]()) { partialResult, transform in
            let newHeader = try transform.initializeAndReturnHeaderData()
            var newResult = try partialResult.map { try transform.transform(data: $0) }
            newResult.append(newHeader)
            return newResult
        }
        let headerData = transformDatas.reversed().reduce(into: Data()) { $0.append($1) }
        if headerData.count > 0 {
            try outputStream.write(data: headerData)
        }
    }

    public func write(data: Data) throws {
        if !hasInitialized {
            try initializeAndWriteHeader()
            hasInitialized = true
        }
        let data = try transforms.reduce(data) { try $1.transform(data: $0) }
        if data.count > 0 {
            try outputStream.write(data: data)
        }
    }

    /// Iterates through each transform, allowing it to finalize the output and write any one-time
    /// footers required by the internal transform implementation.
    public func finalizeAndWriteFooter() throws {
        // For the most part, this follows the same logic as writing of the headers, but in loop after
        // generating the footer data, the list of results is _not_ reversed, resulting in writing the
        // 'innermost' transform footer, followed in order until finishing with the 'outermost' footer
        // data, completing the stream output.
        let transformDatas = try transforms.reduce([Data]()) { partialResult, transform in
            var newResult = try partialResult.map { try transform.transform(data: $0) }
            newResult.append(try transform.finalizeAndReturnFooterData())
            return newResult
        }
        let footerData = transformDatas.reduce(into: Data()) { $0.append($1) }
        if footerData.count > 0 {
            try outputStream.write(data: footerData)
        }
    }

    public func close() throws {
        try finalizeAndWriteFooter()

        if let runLoop {
            outputStream.remove(from: runLoop, forMode: .default)
        }
        try outputStream.close()
    }

    /// Iterates through each transform, allowing it to generate one-time data (headers/footers) required by the
    /// internal transfrom implementation.  The tricky part is the 'inner' transforms need to pass their
    /// generated header to the next transform in the chain to transform is as part of it's regular body data.
    private func buildTransformedValue(
        transforms: [any StreamTransform],
        transformBlock: ((StreamTransform) throws -> Data)
    ) throws -> Data {
        // For each transform in the list, do the following:
        // 1. Iterate over any previously generated value (header/footer) and transform those values
        // 2. Append it's own value (header/footer) to the list to be transformed by any following transforms
        let transformDatas = try transforms.reduce([Data]()) { partialResult, transform in
            var newResult = try partialResult.map { try transform.transform(data: $0) }
            newResult.append(try transformBlock(transform))
            return newResult
        }
        return transformDatas.reduce(into: Data()) { $0.append($1) }
    }

    // MARK: - OutputStreamable passthrough

    public func remove(from runLoop: RunLoop, forMode mode: RunLoop.Mode) {
        self.outputStream.remove(from: runLoop, forMode: mode)
    }

    public func schedule(in runLoop: RunLoop, forMode mode: RunLoop.Mode) {
        self.outputStream.schedule(in: runLoop, forMode: mode)
    }

}

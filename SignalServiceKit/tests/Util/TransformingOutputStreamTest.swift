//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

final class TransformingOutputStreamTest: XCTestCase {

    func testMultipleTransforms() throws {
        let outputStream = TextBackedOutputStream()
        let transformingStream = TransformingOutputStream(
            transforms: [
                TestStreamTransform3(),
                TestStreamTransform2(),
                TestStreamTransform1()
            ],
            outputStream: outputStream
        )
        try transformingStream.write(data: "w".data(using: .utf8)!)
        try transformingStream.write(data: "xx".data(using: .utf8)!)
        try transformingStream.write(data: "yyy".data(using: .utf8)!)
        try transformingStream.write(data: "zzzz".data(using: .utf8)!)
        try transformingStream.close()

        let expected = "H0[H1][{H2}][{|w|}][{|xx|}][{|yyy|}][{|zzzz|}][{F2}][F1]F0"
        XCTAssertEqual(expected, outputStream.result!)
    }

    private class TextBackedOutputStream: OutputStreamable {

        var result: String?
        private var accumulation = Data()

        func write(data: Data) throws {
            accumulation.append(data)
        }

        func close() throws {
            result = String(data: accumulation, encoding: .utf8)
        }

        func remove(from: RunLoop, forMode: RunLoop.Mode) { }

        func schedule(in: RunLoop, forMode: RunLoop.Mode) { }
    }

    private class TestStreamTransform1: StreamTransform {
        func initializeAndReturnHeaderData() throws -> Data { "H0".data(using: .utf8)! }

        func transform(data: Data) throws -> Data {
            var returnData = "[".data(using: .utf8)!
            returnData.append(data)
            returnData.append("]".data(using: .utf8)!)
            return returnData
        }

        func finalizeAndReturnFooterData() throws -> Data { "F0".data(using: .utf8)! }

    }

    private class TestStreamTransform2: StreamTransform {
        func initializeAndReturnHeaderData() throws -> Data { "H1".data(using: .utf8)! }

        func transform(data: Data) throws -> Data {
            var returnData = "{".data(using: .utf8)!
            returnData.append(data)
            returnData.append("}".data(using: .utf8)!)
            return returnData
        }

        func finalizeAndReturnFooterData() throws -> Data { "F1".data(using: .utf8)! }
    }

    private class TestStreamTransform3: StreamTransform {
        func initializeAndReturnHeaderData() throws -> Data { "H2".data(using: .utf8)! }

        func transform(data: Data) throws -> Data {
            var returnData = "|".data(using: .utf8)!
            returnData.append(data)
            returnData.append("|".data(using: .utf8)!)
            return returnData
        }

        func finalizeAndReturnFooterData() throws -> Data { "F2".data(using: .utf8)! }

    }
}

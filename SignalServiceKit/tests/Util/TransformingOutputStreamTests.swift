//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

final class TransformingOutputStreamTests: XCTestCase {

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

        let expected = "H0[H1{H2|w|}][{|xx|}][{|yyy|}][{|zzzz|}][{F2}][F1]F0"
        XCTAssertEqual(expected, String(data: outputStream.accumulation, encoding: .utf8))
    }

    private class TestStreamTransform1: StreamTransform, FinalizableStreamTransform {
        var hasPendingBytes: Bool { false }
        var hasFinalized = false
        private var initialized = false

        private func headerData() -> Data {
            var returnData = Data()
            returnData.append("H0".data(using: .utf8)!)
            return returnData
        }

        func transform(data: Data) throws -> Data {
            var returnData = Data()
            if !initialized {
                initialized = true
                returnData.append(headerData())
            }
            returnData.append("[".data(using: .utf8)!)
            returnData.append(data)
            returnData.append("]".data(using: .utf8)!)
            return returnData
        }

        func finalize() throws -> Data {
            hasFinalized = true
            return "F0".data(using: .utf8)!
        }
    }

    private class TestStreamTransform2: StreamTransform, FinalizableStreamTransform {
        var hasPendingBytes: Bool { false }
        var hasFinalized = false
        private var initialized = false

        private func headerData() -> Data {
            var returnData = Data()
            returnData.append("H1".data(using: .utf8)!)
            return returnData
        }

        func transform(data: Data) throws -> Data {
            var returnData = Data()
            if !initialized {
                initialized = true
                returnData.append(headerData())
            }
            returnData.append("{".data(using: .utf8)!)
            returnData.append(data)
            returnData.append("}".data(using: .utf8)!)
            return returnData
        }

        func finalize() throws -> Data {
            hasFinalized = true
            return "F1".data(using: .utf8)!
        }
    }

    private class TestStreamTransform3: StreamTransform, FinalizableStreamTransform {
        var hasPendingBytes: Bool { false }
        var hasFinalized = false
        private var initialized = false

        private func headerData() -> Data {
            var returnData = Data()
            returnData.append("H2".data(using: .utf8)!)
            return returnData
        }

        func transform(data: Data) throws -> Data {
            var returnData = Data()
            if !initialized {
                initialized = true
                returnData.append(headerData())
            }
            returnData.append("|".data(using: .utf8)!)
            returnData.append(data)
            returnData.append("|".data(using: .utf8)!)
            return returnData
        }

        func finalize() throws -> Data {
            hasFinalized = true
            return "F2".data(using: .utf8)!
        }
    }
}

class TextBackedInputStream: InputStreamable {
    var hasBytesAvailable: Bool { data.count > 0 }

    private var data: Data
    init(data: Data) {
        self.data = data
    }

    func read(maxLength len: Int) throws -> Data {
        let readCount = min(len, data.count)
        let returnData = data.subdata(in: 0..<readCount)
        data = data.subdata(in: readCount..<data.count)
        return returnData
    }

    func close() throws { }

    func remove(from: RunLoop, forMode: RunLoop.Mode) { }

    func schedule(in: RunLoop, forMode: RunLoop.Mode) { }
}

class TextBackedOutputStream: OutputStreamable {

    var accumulation = Data()

    func write(data: Data) throws {
        accumulation.append(data)
    }

    func close() throws {
    }

    func remove(from: RunLoop, forMode: RunLoop.Mode) { }

    func schedule(in: RunLoop, forMode: RunLoop.Mode) { }
}

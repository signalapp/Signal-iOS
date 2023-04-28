//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

class ByteParserTest: XCTestCase {
    func testGetShort_Empty() {
        let parser = ByteParser(data: Data(), littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextUInt16())
        XCTAssertTrue(parser.hasError)
    }

    func testGetShort_littleEndian() {
        let data = Data([0x01, 0x00, 0x00, 0x01, 0x01, 0x01])
        let parser = ByteParser(data: data, littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(1, parser.nextUInt16())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(256, parser.nextUInt16())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(257, parser.nextUInt16())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextUInt16())
        XCTAssertTrue(parser.hasError)
    }

    func testGetShort_bigEndian() {
        let data = Data([0x01, 0x00, 0x00, 0x01, 0x01, 0x01])
        let parser = ByteParser(data: data, littleEndian: false)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(256, parser.nextUInt16())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(1, parser.nextUInt16())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(257, parser.nextUInt16())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextUInt16())
        XCTAssertTrue(parser.hasError)
    }

    func testGetInt_Empty() {
        let parser = ByteParser(data: Data(), littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextUInt32())
        XCTAssertTrue(parser.hasError)
    }

    func testGetInt_littleEndian() {
        let data = Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00])
        let parser = ByteParser(data: data, littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(1, parser.nextUInt32())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(256, parser.nextUInt32())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(257, parser.nextUInt32())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextUInt32())
        XCTAssertTrue(parser.hasError)
    }

    func testGetInt_bigEndian() {
        let data = Data([0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x01])
        let parser = ByteParser(data: data, littleEndian: false)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(1, parser.nextUInt32())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(256, parser.nextUInt32())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(257, parser.nextUInt32())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextUInt32())
        XCTAssertTrue(parser.hasError)
    }

    func testGetLong_Empty() {
        let parser = ByteParser(data: Data(), littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextUInt64())
        XCTAssertTrue(parser.hasError)
    }

    func testGetLong_littleEndian() {
        let data = Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        let parser = ByteParser(data: data, littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(1, parser.nextUInt64())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(256, parser.nextUInt64())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(257, parser.nextUInt64())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextUInt64())
        XCTAssertTrue(parser.hasError)
    }

    func testGetLong_bigEndian() {
        let data = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01])
        let parser = ByteParser(data: data, littleEndian: false)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(1, parser.nextUInt64())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(256, parser.nextUInt64())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(257, parser.nextUInt64())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextUInt64())
        XCTAssertTrue(parser.hasError)
    }

    func testReadZero_Empty() {
        let parser = ByteParser(data: Data(), littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertFalse(parser.readZero(1))
        XCTAssertTrue(parser.hasError)
    }

    func testReadZero() {
        let data = Data([0x00, 0x01, 0x00, 0x00, 0x01, 0x00])
        let parser = ByteParser(data: data, littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertTrue(parser.readZero(1))
        XCTAssertFalse(parser.hasError)

        XCTAssertFalse(parser.readZero(1))
        XCTAssertFalse(parser.hasError)

        XCTAssertTrue(parser.readZero(2))
        XCTAssertFalse(parser.hasError)

        XCTAssertFalse(parser.readZero(2))
        XCTAssertFalse(parser.hasError)

        XCTAssertFalse(parser.readZero(1))
        XCTAssertTrue(parser.hasError)
    }

    func testReadBytes_Empty() {
        let parser = ByteParser(data: Data(), littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertNil(parser.readBytes(1))
        XCTAssertTrue(parser.hasError)
    }

    func testReadBytes() {
        let data = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        let parser = ByteParser(data: data, littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(Data([0x00]), parser.readBytes(1))
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(Data([0x01]), parser.readBytes(1))
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(Data([0x02, 0x03]), parser.readBytes(2))
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(Data([0x04, 0x05]), parser.readBytes(2))
        XCTAssertFalse(parser.hasError)

        XCTAssertNil(parser.readBytes(1))
        XCTAssertTrue(parser.hasError)
    }
}

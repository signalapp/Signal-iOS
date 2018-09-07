//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal

class ByteParserTest: SignalBaseTest {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testGetShort_Empty() {
        let parser = ByteParser(data: Data(), littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextShort())
        XCTAssertTrue(parser.hasError)
    }

    func testGetShort_littleEndian() {
        let data = Data(bytes: [0x01, 0x00, 0x00, 0x01, 0x01, 0x01 ])
        let parser = ByteParser(data: data, littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(1, parser.nextShort())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(256, parser.nextShort())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(257, parser.nextShort())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextShort())
        XCTAssertTrue(parser.hasError)
    }

    func testGetShort_bigEndian() {
        let data = Data(bytes: [0x01, 0x00, 0x00, 0x01, 0x01, 0x01 ])
        let parser = ByteParser(data: data, littleEndian: false)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(256, parser.nextShort())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(1, parser.nextShort())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(257, parser.nextShort())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextShort())
        XCTAssertTrue(parser.hasError)
    }

    func testGetInt_Empty() {
        let parser = ByteParser(data: Data(), littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextInt())
        XCTAssertTrue(parser.hasError)
    }

    func testGetInt_littleEndian() {
        let data = Data(bytes: [0x01, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00 ])
        let parser = ByteParser(data: data, littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(1, parser.nextInt())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(256, parser.nextInt())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(257, parser.nextInt())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextInt())
        XCTAssertTrue(parser.hasError)
    }

    func testGetInt_bigEndian() {
        let data = Data(bytes: [0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x01 ])
        let parser = ByteParser(data: data, littleEndian: false)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(1, parser.nextInt())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(256, parser.nextInt())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(257, parser.nextInt())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextInt())
        XCTAssertTrue(parser.hasError)
    }

    func testGetLong_Empty() {
        let parser = ByteParser(data: Data(), littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextLong())
        XCTAssertTrue(parser.hasError)
    }

    func testGetLong_littleEndian() {
        let data = Data(bytes: [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ])
        let parser = ByteParser(data: data, littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(1, parser.nextLong())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(256, parser.nextLong())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(257, parser.nextLong())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextLong())
        XCTAssertTrue(parser.hasError)
    }

    func testGetLong_bigEndian() {
        let data = Data(bytes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01 ])
        let parser = ByteParser(data: data, littleEndian: false)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(1, parser.nextLong())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(256, parser.nextLong())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(257, parser.nextLong())
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(0, parser.nextLong())
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
        let data = Data(bytes: [0x00, 0x01, 0x00, 0x00, 0x01, 0x00])
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
        let data = Data(bytes: [0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        let parser = ByteParser(data: data, littleEndian: true)
        XCTAssertNotNil(parser)
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(Data(bytes: [0x00 ]), parser.readBytes(1))
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(Data(bytes: [0x01 ]), parser.readBytes(1))
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(Data(bytes: [0x02, 0x03]), parser.readBytes(2))
        XCTAssertFalse(parser.hasError)

        XCTAssertEqual(Data(bytes: [0x04, 0x05]), parser.readBytes(2))
        XCTAssertFalse(parser.hasError)

        XCTAssertNil(parser.readBytes(1))
        XCTAssertTrue(parser.hasError)
    }
}

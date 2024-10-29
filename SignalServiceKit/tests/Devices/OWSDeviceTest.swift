//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

class OWSDeviceTest: XCTestCase {
    private let inMemoryDB = InMemoryDB()

    // MARK: - Round trip

    func testRoundTrip() {
        for (idx, (constant, _)) in OWSDevice.constants.enumerated() {
            inMemoryDB.insert(record: constant)

            let deserialized = inMemoryDB.fetchExactlyOne(modelType: OWSDevice.self)

            guard let deserialized else {
                XCTFail("Failed to fetch constant \(idx)!")
                continue
            }

            do {
                try deserialized.validate(against: constant)
            } catch ValidatableModelError.failedToValidate {
                XCTFail("Failed to validate constant \(idx)!")
            } catch {
                XCTFail("Unexpected error while validating constant \(idx)!")
            }

            inMemoryDB.remove(model: deserialized)
        }
    }

    // MARK: - Hardcoded constant data

    enum HardcodedDataTestMode {
        case runTest
        case printStrings

        /// Toggle this to use ``testHardcodedJsonDataDecodes()`` to print
        /// hardcoded strings, for example when adding new constants.
        static let mode: Self = .runTest
    }

    func testHardcodedJsonDataDecodes() {
        switch HardcodedDataTestMode.mode {
        case .printStrings:
            OWSDevice.printHardcodedJsonDataForConstants()
        case .runTest:
            for (idx, (constant, jsonData)) in OWSDevice.constants.enumerated() {
                do {
                    let decoded = try JSONDecoder().decode(OWSDevice.self, from: jsonData)
                    try constant.validate(against: decoded)
                } catch let error where error is DecodingError {
                    XCTFail("Failed to decode JSON model for constant \(idx): \(error)")
                } catch ValidatableModelError.failedToValidate {
                    XCTFail("Failed to validate JSON-decoded model for constant \(idx)")
                } catch {
                    XCTFail("Unexpected error for constant \(idx)")
                }
            }
        }
    }
}

extension OWSDevice: ValidatableModel {
    static let constants: [(OWSDevice, jsonData: Data)] = [
        (
            OWSDevice(
                deviceId: 1,
                encryptedName: "UklQIE5hdGhhbiBTaGVsbHkgLSBtaXNzIHlvdSwgbWFuLgo=",
                createdAt: Date(millisecondsSince1970: 814929600000),
                lastSeenAt: Date(millisecondsSince1970: 1680897600000)
            ),
            Data(#"{"createdAt":-163377600,"deviceId":1,"lastSeenAt":702590400,"uniqueId":"9C1E5061-AC5D-4830-983E-75E355C03192","name":"UklQIE5hdGhhbiBTaGVsbHkgLSBtaXNzIHlvdSwgbWFuLgo=","recordType":33}"#.utf8)
        ),
        (
            OWSDevice(
                deviceId: 12,
                encryptedName: nil,
                createdAt: Date(millisecondsSince1970: 0),
                lastSeenAt: Date(millisecondsSince1970: 1)
            ),
            Data(#"{"createdAt":-978307200,"deviceId":12,"uniqueId":"E24B6A98-B342-4A0C-9B82-BB45915853B0","lastSeenAt":-978307199.99899995,"recordType":33}"#.utf8)
        )
    ]

    func validate(against: OWSDevice) throws {
        guard
            deviceId == against.deviceId,
            encryptedName == against.encryptedName,
            createdAt == against.createdAt,
            lastSeenAt == against.lastSeenAt
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}

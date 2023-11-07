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
    static let constants: [(OWSDevice, base64JsonData: Data)] = [
        (
            OWSDevice(
                deviceId: 1,
                encryptedName: "UklQIE5hdGhhbiBTaGVsbHkgLSBtaXNzIHlvdSwgbWFuLgo=",
                createdAt: Date(millisecondsSince1970: 814929600000),
                lastSeenAt: Date(millisecondsSince1970: 1680897600000)
            ),
            Data(base64Encoded: "eyJjcmVhdGVkQXQiOi0xNjMzNzc2MDAsImRldmljZUlkIjoxLCJsYXN0U2VlbkF0Ijo3MDI1OTA0MDAsInVuaXF1ZUlkIjoiOUMxRTUwNjEtQUM1RC00ODMwLTk4M0UtNzVFMzU1QzAzMTkyIiwibmFtZSI6IlVrbFFJRTVoZEdoaGJpQlRhR1ZzYkhrZ0xTQnRhWE56SUhsdmRTd2diV0Z1TGdvPSIsInJlY29yZFR5cGUiOjMzfQ==")!
        ),
        (
            OWSDevice(
                deviceId: 12,
                encryptedName: nil,
                createdAt: Date(millisecondsSince1970: 0),
                lastSeenAt: Date(millisecondsSince1970: 1)
            ),
            Data(base64Encoded: "eyJjcmVhdGVkQXQiOi05NzgzMDcyMDAsImRldmljZUlkIjoxMiwidW5pcXVlSWQiOiJFMjRCNkE5OC1CMzQyLTRBMEMtOUI4Mi1CQjQ1OTE1ODUzQjAiLCJsYXN0U2VlbkF0IjotOTc4MzA3MTk5Ljk5ODk5OTk1LCJyZWNvcmRUeXBlIjozM30=")!
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

//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

class KeyBackupServiceTests: SSKBaseTestSwift {
    struct Vector: Codable {
        let pin: String
        let backupId: Data
        let argon2Hash: Data
        let masterKey: Data
        let kbsAccessKey: Data
        let ivAndCipher: Data
        let registrationLock: String
    }

    lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dataDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let data = Data.data(fromHex: string) else { throw OWSAssertionError("Invalid data") }
            return data
        }
        return decoder
    }()

    func test_vectors() throws {
        let vectorsUrl = Bundle(for: type(of: self)).url(forResource: "kbs_vectors", withExtension: "json")!
        let jsonData = try Data(contentsOf: vectorsUrl)
        let vectors = try decoder.decode([Vector].self, from: jsonData)

        for vector in vectors {
            let (encryptionKey, accessKey) = try KeyBackupService.deriveEncryptionKeyAndAccessKey(pin: vector.pin, backupId: vector.backupId)

            XCTAssertEqual(vector.argon2Hash, encryptionKey + accessKey)
            XCTAssertEqual(vector.kbsAccessKey, accessKey)

            let ivAndCipher = try KeyBackupService.encryptMasterKey(vector.masterKey, encryptionKey: encryptionKey)

            XCTAssertEqual(vector.ivAndCipher, ivAndCipher)

            let decryptedMasterKey = try KeyBackupService.decryptMasterKey(ivAndCipher, encryptionKey: encryptionKey)

            XCTAssertEqual(vector.masterKey, decryptedMasterKey)

            databaseStorage.write { transaction in
                KeyBackupService.store(vector.masterKey, pinType: .init(forPin: vector.pin), encodedVerificationString: "", transaction: transaction)
            }

            let registrationLockToken = KeyBackupService.deriveRegistrationLockToken()

            XCTAssertEqual(vector.registrationLock, registrationLockToken)
        }
    }

    func test_pinVerification() throws {
        let pin = "apassword"
        let backupId = Data.data(
            fromHex: "202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F"
        )!
        let expectedEncodedVerificationString = "$argon2id$v=19$m=8192,t=2,p=1$ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8$EQqNdaL3vwVMfYiZz10pMuaDq6x6VRuCfDlNEvSVBLllb5nfddllVooJtJ/LcFRXmQJXcV47OBoTraq5LXZCnw"

        let encodedVerificationString = try KeyBackupService.deriveEncodedVerificationString(pin: pin, backupId: backupId)

        XCTAssertEqual(expectedEncodedVerificationString, encodedVerificationString)

        databaseStorage.write { transaction in
            KeyBackupService.store(Data(repeating: 0x00, count: 32), pinType: .init(forPin: pin), encodedVerificationString: encodedVerificationString, transaction: transaction)
        }

        // The correct PIN returns as valid.
        AssertPin(pin, isValid: true)

        // The incorrect PIN returns as invalid.
        AssertPin("notmypassword", isValid: false)
    }

    func AssertPin(
        _ pin: String,
        isValid expectedResult: Bool,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let expectation = XCTestExpectation(description: "Verify Pin")
        KeyBackupService.verifyPin(pin) { isValid in
            XCTAssertEqual(isValid, expectedResult, message, file: file, line: line)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
}

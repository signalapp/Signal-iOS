//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct CipherContextTest {
    private let encryptionKey = Data(count: 32)
    private let initializationVector = Data(count: 16)
    private let plaintextData = Data("ABCD1234ABCD1234A".utf8)
    private let encryptedData = Data(base64Encoded: "EAhaOhrka0rMDye55N31YaaqvM/Su01ZZY0/mtDGQ1c=")!

    @Test
    func testEncrypt() throws {
        let context = try CipherContext(
            operation: .encrypt,
            algorithm: .aes,
            options: .pkcs7Padding,
            key: encryptionKey,
            iv: initializationVector,
        )
        var encryptedData = Data()
        encryptedData += try context.update(plaintextData)
        encryptedData += try context.finalize()
        #expect(encryptedData == self.encryptedData, "\(encryptedData.base64EncodedString())")
    }

    @Test
    func testDecrypt() throws {
        let context = try CipherContext(
            operation: .decrypt,
            algorithm: .aes,
            options: .pkcs7Padding,
            key: encryptionKey,
            iv: initializationVector,
        )
        var plaintextData = Data()
        plaintextData += try context.update(encryptedData)
        plaintextData += try context.finalize()
        #expect(plaintextData == self.plaintextData, "\(plaintextData.base64EncodedString())")
    }
}

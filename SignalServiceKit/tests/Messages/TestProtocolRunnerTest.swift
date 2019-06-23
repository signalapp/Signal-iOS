//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class TestProtocolRunnerTest: SSKBaseTestSwift {

    var aliceClient: FakeSignalClient!
    var bobClient: FakeSignalClient!

    override func setUp() {
        super.setUp()
        aliceClient = FakeSignalClient.generate(e164Identifier: "alice")
        bobClient = FakeSignalClient.generate(e164Identifier: "bob")
    }

    let runner = TestProtocolRunner()

    func test_roundtrip() {
        try! runner.initialize(senderClient: aliceClient, recipientClient: bobClient, protocolContext: nil)

        let plaintext = "Those who stands for nothing will fall for anything"
        let cipherMessage = try! runner.encrypt(plaintext: plaintext.data(using: .utf8)!,
                                                senderClient: aliceClient,
                                                recipientE164: bobClient.e164Identifier,
                                                protocolContext: nil)

        let decrypted = try! runner.decrypt(cipherMessage: cipherMessage,
                                            recipientClient: bobClient,
                                            senderE164: aliceClient.e164Identifier,
                                            protocolContext: nil)

        let decryptedText = String(data: decrypted, encoding: .utf8)!
        XCTAssertEqual(plaintext, decryptedText)
    }

    func test_multiple() {
        try! runner.initialize(senderClient: aliceClient, recipientClient: bobClient, protocolContext: nil)

        // two encrypts
        let plaintext1 = "Those who stands for nothing will fall for anything"
        let cipherMessage1 = try! runner.encrypt(plaintext: plaintext1.data(using: .utf8)!,
                                                 senderClient: aliceClient,
                                                 recipientE164: bobClient.e164Identifier,
                                                 protocolContext: nil)

        let plaintext2 = "Do not despair when your enemy attacks you."
        let cipherMessage2 = try! runner.encrypt(plaintext: plaintext2.data(using: .utf8)!,
                                                 senderClient: aliceClient,
                                                 recipientE164: bobClient.e164Identifier,
                                                 protocolContext: nil)

        // two decrypts
        let decrypted1 = try! runner.decrypt(cipherMessage: cipherMessage1,
                                             recipientClient: bobClient,
                                             senderE164: aliceClient.e164Identifier,
                                             protocolContext: nil)

        let decrypted2 = try! runner.decrypt(cipherMessage: cipherMessage2,
                                             recipientClient: bobClient,
                                             senderE164: aliceClient.e164Identifier,
                                             protocolContext: nil)

        let decryptedText1 = String(data: decrypted1, encoding: .utf8)!
        XCTAssertEqual(plaintext1, decryptedText1)

        let decryptedText2 = String(data: decrypted2, encoding: .utf8)!
        XCTAssertEqual(plaintext2, decryptedText2)
    }

    func test_outOfOrder() {
        try! runner.initialize(senderClient: aliceClient, recipientClient: bobClient, protocolContext: nil)

        // two encrypts
        let plaintext1 = "Those who stands for nothing will fall for anything"
        let cipherMessage1 = try! runner.encrypt(plaintext: plaintext1.data(using: .utf8)!,
                                                 senderClient: aliceClient,
                                                 recipientE164: bobClient.e164Identifier,
                                                 protocolContext: nil)

        let plaintext2 = "Do not despair when your enemy attacks you."
        let cipherMessage2 = try! runner.encrypt(plaintext: plaintext2.data(using: .utf8)!,
                                                 senderClient: aliceClient,
                                                 recipientE164: bobClient.e164Identifier,
                                                 protocolContext: nil)

        // decrypt second message first
        let decrypted2 = try! runner.decrypt(cipherMessage: cipherMessage2,
                                             recipientClient: bobClient,
                                             senderE164: aliceClient.e164Identifier,
                                             protocolContext: nil)

        let decrypted1 = try! runner.decrypt(cipherMessage: cipherMessage1,
                                             recipientClient: bobClient,
                                             senderE164: aliceClient.e164Identifier,
                                             protocolContext: nil)

        let decryptedText1 = String(data: decrypted1, encoding: .utf8)!
        XCTAssertEqual(plaintext1, decryptedText1)

        let decryptedText2 = String(data: decrypted2, encoding: .utf8)!
        XCTAssertEqual(plaintext2, decryptedText2)
    }

    func test_localClient() {
        SSKEnvironment.shared.identityManager.generateNewIdentityKey()
        SSKEnvironment.shared.tsAccountManager.registerForTests(withLocalNumber: "+13235551234",
                                                                uuid: UUID())
        let localClient = LocalSignalClient()

        write { transaction in
            try! self.runner.initialize(senderClient: self.bobClient,
                                        recipientClient: localClient,
                                        protocolContext: transaction)

            let plaintext = "Those who stands for nothing will fall for anything"
            let cipherMessage = try! self.runner.encrypt(plaintext: plaintext.data(using: .utf8)!,
                                                         senderClient: self.bobClient,
                                                         recipientE164: localClient.e164Identifier,
                                                         protocolContext: transaction)

            let decrypted = try! self.runner.decrypt(cipherMessage: cipherMessage,
                                                     recipientClient: localClient,
                                                     senderE164: self.bobClient.e164Identifier,
                                                     protocolContext: transaction)

            let decryptedText = String(data: decrypted, encoding: .utf8)!
            XCTAssertEqual(plaintext, decryptedText)
        }
    }
}

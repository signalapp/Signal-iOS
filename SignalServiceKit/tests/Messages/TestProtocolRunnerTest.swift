//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class TestProtocolRunnerTest: SSKBaseTestSwift {

    var aliceClient: FakeSignalClient!
    var bobClient: FakeSignalClient!

    override func setUp() {
        super.setUp()
        aliceClient = FakeSignalClient.generate(e164Identifier: "+122233alice")
        bobClient = FakeSignalClient.generate(e164Identifier: "+12223334bob")
    }

    let runner = TestProtocolRunner()

    func test_roundtrip() {
        write { transaction in
            try! self.runner.initialize(senderClient: self.aliceClient, recipientClient: self.bobClient, transaction: transaction)

            let plaintext = "Those who stands for nothing will fall for anything"
            let cipherMessage = try! self.runner.encrypt(plaintext: plaintext.data(using: .utf8)!,
                                                         senderClient: self.aliceClient,
                                                         recipientAccountId: self.bobClient.accountId(transaction: transaction),
                                                         protocolContext: nil)

            let decrypted = try! self.runner.decrypt(cipherMessage: cipherMessage,
                                                     recipientClient: self.bobClient,
                                                     senderAccountId: self.aliceClient.accountId(transaction: transaction),
                                                     protocolContext: nil)

            let decryptedText = String(data: decrypted, encoding: .utf8)!
            XCTAssertEqual(plaintext, decryptedText)
        }
    }

    func test_multiple() {
        write { transaction in
            try! self.runner.initialize(senderClient: self.aliceClient, recipientClient: self.bobClient, transaction: transaction)

            // two encrypts
            let plaintext1 = "Those who stands for nothing will fall for anything"
            let cipherMessage1 = try! self.runner.encrypt(plaintext: plaintext1.data(using: .utf8)!,
                                                     senderClient: self.aliceClient,
                                                     recipientAccountId: self.bobClient.accountId(transaction: transaction),
                                                     protocolContext: nil)

            let plaintext2 = "Do not despair when your enemy attacks you."
            let cipherMessage2 = try! self.runner.encrypt(plaintext: plaintext2.data(using: .utf8)!,
                                                     senderClient: self.aliceClient,
                                                     recipientAccountId: self.bobClient.accountId(transaction: transaction),
                                                     protocolContext: nil)

            // two decrypts
            let decrypted1 = try! self.runner.decrypt(cipherMessage: cipherMessage1,
                                                 recipientClient: self.bobClient,
                                                 senderAccountId: self.aliceClient.accountId(transaction: transaction),
                                                 protocolContext: nil)

            let decrypted2 = try! self.runner.decrypt(cipherMessage: cipherMessage2,
                                                 recipientClient: self.bobClient,
                                                 senderAccountId: self.aliceClient.accountId(transaction: transaction),
                                                 protocolContext: nil)

            let decryptedText1 = String(data: decrypted1, encoding: .utf8)!
            XCTAssertEqual(plaintext1, decryptedText1)

            let decryptedText2 = String(data: decrypted2, encoding: .utf8)!
            XCTAssertEqual(plaintext2, decryptedText2)
        }
    }

    func test_outOfOrder() {
        write { transaction in
            try! self.runner.initialize(senderClient: self.aliceClient, recipientClient: self.bobClient, transaction: transaction)

            // two encrypts
            let plaintext1 = "Those who stands for nothing will fall for anything"
            let cipherMessage1 = try! self.runner.encrypt(plaintext: plaintext1.data(using: .utf8)!,
                                                     senderClient: self.aliceClient,
                                                     recipientAccountId: self.bobClient.accountId(transaction: transaction),
                                                     protocolContext: nil)

            let plaintext2 = "Do not despair when your enemy attacks you."
            let cipherMessage2 = try! self.runner.encrypt(plaintext: plaintext2.data(using: .utf8)!,
                                                     senderClient: self.aliceClient,
                                                     recipientAccountId: self.bobClient.accountId(transaction: transaction),
                                                     protocolContext: nil)

            // decrypt second message first
            let decrypted2 = try! self.runner.decrypt(cipherMessage: cipherMessage2,
                                                 recipientClient: self.bobClient,
                                                 senderAccountId: self.aliceClient.accountId(transaction: transaction),
                                                 protocolContext: nil)

            let decrypted1 = try! self.runner.decrypt(cipherMessage: cipherMessage1,
                                                 recipientClient: self.bobClient,
                                                 senderAccountId: self.aliceClient.accountId(transaction: transaction),
                                                 protocolContext: nil)

            let decryptedText1 = String(data: decrypted1, encoding: .utf8)!
            XCTAssertEqual(plaintext1, decryptedText1)

            let decryptedText2 = String(data: decrypted2, encoding: .utf8)!
            XCTAssertEqual(plaintext2, decryptedText2)
        }
    }

    func test_localClient_receives() {
        SSKEnvironment.shared.identityManager.generateNewIdentityKey()
        SSKEnvironment.shared.tsAccountManager.registerForTests(withLocalNumber: "+13235551234",
                                                                uuid: UUID())
        let localClient = LocalSignalClient()

        write { transaction in
            try! self.runner.initialize(senderClient: self.bobClient,
                                        recipientClient: localClient,
                                        transaction: transaction)

            let plaintext = "Those who stands for nothing will fall for anything"
            let cipherMessage = try! self.runner.encrypt(plaintext: plaintext.data(using: .utf8)!,
                                                         senderClient: self.bobClient,
                                                         recipientAccountId: localClient.accountId(transaction: transaction),
                                                         protocolContext: transaction)

            let decrypted = try! self.runner.decrypt(cipherMessage: cipherMessage,
                                                     recipientClient: localClient,
                                                     senderAccountId: self.bobClient.accountId(transaction: transaction),
                                                     protocolContext: transaction)

            let decryptedText = String(data: decrypted, encoding: .utf8)!
            XCTAssertEqual(plaintext, decryptedText)
        }
    }

    func test_localClient_sends() {
        SSKEnvironment.shared.identityManager.generateNewIdentityKey()
        SSKEnvironment.shared.tsAccountManager.registerForTests(withLocalNumber: "+13235551234",
                                                                uuid: UUID())
        let localClient = LocalSignalClient()

        write { transaction in
            try! self.runner.initialize(senderClient: localClient,
                                        recipientClient: self.bobClient,
                                        transaction: transaction)

            let plaintext = "Those who stands for nothing will fall for anything"
            let cipherMessage = try! self.runner.encrypt(plaintext: plaintext.data(using: .utf8)!,
                                                         senderClient: localClient,
                                                         recipientAccountId: self.bobClient.accountId(transaction: transaction),
                                                         protocolContext: transaction)

            let decrypted = try! self.runner.decrypt(cipherMessage: cipherMessage,
                                                     recipientClient: self.bobClient,
                                                     senderAccountId: localClient.accountId(transaction: transaction),
                                                     protocolContext: transaction)

            let decryptedText = String(data: decrypted, encoding: .utf8)!
            XCTAssertEqual(plaintext, decryptedText)
        }
    }
}

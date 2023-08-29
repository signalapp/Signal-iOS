//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import LibSignalClient

@testable import SignalServiceKit

class TestProtocolRunnerTest: SSKBaseTestSwift {

    var aliceClient: FakeSignalClient!
    var bobClient: FakeSignalClient!

    override func setUp() {
        super.setUp()
        aliceClient = FakeSignalClient.generate(e164Identifier: "+122233alice")
        bobClient = FakeSignalClient.generate(e164Identifier: "+12223334bob")

        tsAccountManager.registerForTests(withLocalNumber: "+13235551234", uuid: UUID())
    }

    let runner = TestProtocolRunner()

    func test_roundtrip() {
        write { transaction in
            try! self.runner.initialize(senderClient: self.aliceClient, recipientClient: self.bobClient, transaction: transaction)

            let plaintext = "Those who stands for nothing will fall for anything"
            let cipherMessage = try! self.runner.encrypt(plaintext.data(using: .utf8)!,
                                                         senderClient: self.aliceClient,
                                                         recipient: self.bobClient.protocolAddress,
                                                         context: NullContext())

            let decrypted = try! self.runner.decrypt(cipherMessage,
                                                     recipientClient: self.bobClient,
                                                     sender: self.aliceClient.protocolAddress,
                                                     context: NullContext())

            let decryptedText = String(data: decrypted, encoding: .utf8)!
            XCTAssertEqual(plaintext, decryptedText)
        }
    }

    func test_multiple() {
        write { transaction in
            try! self.runner.initialize(senderClient: self.aliceClient, recipientClient: self.bobClient, transaction: transaction)

            // two encrypts
            let plaintext1 = "Those who stands for nothing will fall for anything"
            let cipherMessage1 = try! self.runner.encrypt(plaintext1.data(using: .utf8)!,
                                                          senderClient: self.aliceClient,
                                                          recipient: self.bobClient.protocolAddress,
                                                          context: NullContext())

            let plaintext2 = "Do not despair when your enemy attacks you."
            let cipherMessage2 = try! self.runner.encrypt(plaintext2.data(using: .utf8)!,
                                                          senderClient: self.aliceClient,
                                                          recipient: self.bobClient.protocolAddress,
                                                          context: NullContext())

            // two decrypts
            let decrypted1 = try! self.runner.decrypt(cipherMessage1,
                                                      recipientClient: self.bobClient,
                                                      sender: self.aliceClient.protocolAddress,
                                                      context: NullContext())

            let decrypted2 = try! self.runner.decrypt(cipherMessage2,
                                                      recipientClient: self.bobClient,
                                                      sender: self.aliceClient.protocolAddress,
                                                      context: NullContext())

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
            let cipherMessage1 = try! self.runner.encrypt(plaintext1.data(using: .utf8)!,
                                                          senderClient: self.aliceClient,
                                                          recipient: self.bobClient.protocolAddress,
                                                          context: NullContext())

            let plaintext2 = "Do not despair when your enemy attacks you."
            let cipherMessage2 = try! self.runner.encrypt(plaintext2.data(using: .utf8)!,
                                                          senderClient: self.aliceClient,
                                                          recipient: self.bobClient.protocolAddress,
                                                          context: NullContext())

            // decrypt second message first
            let decrypted2 = try! self.runner.decrypt(cipherMessage2,
                                                      recipientClient: self.bobClient,
                                                      sender: self.aliceClient.protocolAddress,
                                                      context: NullContext())

            let decrypted1 = try! self.runner.decrypt(cipherMessage1,
                                                      recipientClient: self.bobClient,
                                                      sender: self.aliceClient.protocolAddress,
                                                      context: NullContext())

            let decryptedText1 = String(data: decrypted1, encoding: .utf8)!
            XCTAssertEqual(plaintext1, decryptedText1)

            let decryptedText2 = String(data: decrypted2, encoding: .utf8)!
            XCTAssertEqual(plaintext2, decryptedText2)
        }
    }

    func test_localClient_receives() {
        let identityManager = DependenciesBridge.shared.identityManager
        identityManager.generateAndPersistNewIdentityKey(for: .aci)
        Self.tsAccountManager.registerForTests(withLocalNumber: "+13235551234", uuid: UUID())
        let localClient = LocalSignalClient()

        write { transaction in
            try! self.runner.initialize(senderClient: self.bobClient,
                                        recipientClient: localClient,
                                        transaction: transaction)

            let plaintext = "Those who stands for nothing will fall for anything"
            let cipherMessage = try! self.runner.encrypt(plaintext.data(using: .utf8)!,
                                                         senderClient: self.bobClient,
                                                         recipient: localClient.protocolAddress,
                                                         context: transaction)

            let decrypted = try! self.runner.decrypt(cipherMessage,
                                                     recipientClient: localClient,
                                                     sender: self.bobClient.protocolAddress,
                                                     context: transaction)

            let decryptedText = String(data: decrypted, encoding: .utf8)!
            XCTAssertEqual(plaintext, decryptedText)
        }
    }

    func test_localClient_sends() {
        let identityManager = DependenciesBridge.shared.identityManager
        identityManager.generateAndPersistNewIdentityKey(for: .aci)
        Self.tsAccountManager.registerForTests(withLocalNumber: "+13235551234", uuid: UUID())
        let localClient = LocalSignalClient()

        write { transaction in
            try! self.runner.initialize(senderClient: localClient,
                                        recipientClient: self.bobClient,
                                        transaction: transaction)

            let plaintext = "Those who stands for nothing will fall for anything"
            let cipherMessage = try! self.runner.encrypt(plaintext.data(using: .utf8)!,
                                                         senderClient: localClient,
                                                         recipient: self.bobClient.protocolAddress,
                                                         context: transaction)

            let decrypted = try! self.runner.decrypt(cipherMessage,
                                                     recipientClient: self.bobClient,
                                                     sender: localClient.protocolAddress,
                                                     context: transaction)

            let decryptedText = String(data: decrypted, encoding: .utf8)!
            XCTAssertEqual(plaintext, decryptedText)
        }
    }
}

// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import PromiseKit
import GRDB
import Sodium
import SessionSnodeKit
import SessionUtilitiesKit

import Quick
import Nimble

@testable import SessionMessagingKit

class OpenGroupAPISpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        var mockStorage: Storage!
        var mockSodium: MockSodium!
        var mockAeadXChaCha20Poly1305Ietf: MockAeadXChaCha20Poly1305Ietf!
        var mockSign: MockSign!
        var mockGenericHash: MockGenericHash!
        var mockEd25519: MockEd25519!
        var mockNonce16Generator: MockNonce16Generator!
        var mockNonce24Generator: MockNonce24Generator!
        var dependencies: SMKDependencies!
        
        var response: (OnionRequestResponseInfoType, Codable)? = nil
        var pollResponse: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable?)]?
        var error: Error?

        describe("an OpenGroupAPI") {
            // MARK: - Configuration
            
            beforeEach {
                mockStorage = Storage(
                    customWriter: try! DatabaseQueue(),
                    customMigrations: [
                        SNUtilitiesKit.migrations(),
                        SNMessagingKit.migrations()
                    ]
                )
                mockSodium = MockSodium()
                mockAeadXChaCha20Poly1305Ietf = MockAeadXChaCha20Poly1305Ietf()
                mockSign = MockSign()
                mockGenericHash = MockGenericHash()
                mockNonce16Generator = MockNonce16Generator()
                mockNonce24Generator = MockNonce24Generator()
                mockEd25519 = MockEd25519()
                dependencies = SMKDependencies(
                    onionApi: TestOnionRequestAPI.self,
                    storage: mockStorage,
                    sodium: mockSodium,
                    genericHash: mockGenericHash,
                    sign: mockSign,
                    aeadXChaCha20Poly1305Ietf: mockAeadXChaCha20Poly1305Ietf,
                    ed25519: mockEd25519,
                    nonceGenerator16: mockNonce16Generator,
                    nonceGenerator24: mockNonce24Generator,
                    date: Date(timeIntervalSince1970: 1234567890)
                )
                
                mockStorage.write { db in
                    try Identity(variant: .x25519PublicKey, data: Data.data(fromHex: TestConstants.publicKey)!).insert(db)
                    try Identity(variant: .x25519PrivateKey, data: Data.data(fromHex: TestConstants.privateKey)!).insert(db)
                    try Identity(variant: .ed25519PublicKey, data: Data.data(fromHex: TestConstants.edPublicKey)!).insert(db)
                    try Identity(variant: .ed25519SecretKey, data: Data.data(fromHex: TestConstants.edSecretKey)!).insert(db)
                    
                    try OpenGroup(
                        server: "testServer",
                        roomToken: "testRoom",
                        publicKey: TestConstants.publicKey,
                        isActive: true,
                        name: "Test",
                        roomDescription: nil,
                        imageId: nil,
                        userCount: 0,
                        infoUpdates: 0,
                        sequenceNumber: 0,
                        inboxLatestMessageId: 0,
                        outboxLatestMessageId: 0
                    ).insert(db)
                    try Capability(openGroupServer: "testserver", variant: .sogs, isMissing: false).insert(db)
                }
                
                mockGenericHash.when { $0.hash(message: anyArray(), outputLength: any()) }.thenReturn([])
                mockSodium
                    .when { $0.blindedKeyPair(serverPublicKey: any(), edKeyPair: any(), genericHash: mockGenericHash) }
                    .thenReturn(
                        Box.KeyPair(
                            publicKey: Data.data(fromHex: TestConstants.publicKey)!.bytes,
                            secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                        )
                    )
                mockSodium
                    .when {
                        $0.sogsSignature(
                            message: anyArray(),
                            secretKey: anyArray(),
                            blindedSecretKey: anyArray(),
                            blindedPublicKey: anyArray()
                        )
                    }
                    .thenReturn("TestSogsSignature".bytes)
                mockSign.when { $0.signature(message: anyArray(), secretKey: anyArray()) }.thenReturn("TestSignature".bytes)
                mockEd25519.when { try $0.sign(data: anyArray(), keyPair: any()) }.thenReturn("TestStandardSignature".bytes)
                
                mockNonce16Generator
                    .when { $0.nonce() }
                    .thenReturn(Data(base64Encoded: "pK6YRtQApl4NhECGizF0Cg==")!.bytes)
                mockNonce24Generator
                    .when { $0.nonce() }
                    .thenReturn(Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!.bytes)
            }

            afterEach {
                mockStorage = nil
                mockSodium = nil
                mockAeadXChaCha20Poly1305Ietf = nil
                mockSign = nil
                mockGenericHash = nil
                mockEd25519 = nil
                dependencies = nil
                
                response = nil
                pollResponse = nil
                error = nil
            }
            
            // MARK: - Batching & Polling
    
            context("when polling") {
                context("and given a correct response") {
                    beforeEach {
                        class TestApi: TestOnionRequestAPI {
                            override class var mockResponse: Data? {
                                let responses: [Data] = [
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: OpenGroupAPI.Capabilities(capabilities: [], missing: nil),
                                            failedToParseBody: false
                                        )
                                    ),
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: try! JSONDecoder().decode(
                                                OpenGroupAPI.RoomPollInfo.self,
                                                from: """
                                                {
                                                    \"token\":\"test\",
                                                    \"active_users\":1,
                                                    \"read\":true,
                                                    \"write\":true,
                                                    \"upload\":true
                                                }
                                                """.data(using: .utf8)!
                                            ),
                                            failedToParseBody: false
                                        )
                                    ),
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: [OpenGroupAPI.Message](),
                                            failedToParseBody: false
                                        )
                                    )
                                ]
                                
                                return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
                            }
                        }
                        
                        dependencies = dependencies.with(onionApi: TestApi.self)
                    }
                    
                    it("generates the correct request") {
                        mockStorage
                            .read { db in
                                OpenGroupAPI.poll(
                                    db,
                                    server: "testserver",
                                    hasPerformedInitialPoll: false,
                                    timeSinceLastPoll: 0,
                                    using: dependencies
                                )
                            }
                            .get { result in pollResponse = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(pollResponse)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(error?.localizedDescription).to(beNil())
                        
                        // Validate the response data
                        expect(pollResponse?.values).to(haveCount(3))
                        expect(pollResponse?.keys).to(contain(.capabilities))
                        expect(pollResponse?.keys).to(contain(.roomPollInfo("testRoom", 0)))
                        expect(pollResponse?.keys).to(contain(.roomMessagesRecent("testRoom")))
                        expect(pollResponse?[.capabilities]?.0).to(beAKindOf(TestOnionRequestAPI.ResponseInfo.self))
                        
                        // Validate request data
                        let requestData: TestOnionRequestAPI.RequestData? = (pollResponse?[.capabilities]?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                        expect(requestData?.urlString).to(equal("testserver/batch"))
                        expect(requestData?.httpMethod).to(equal("POST"))
                        expect(requestData?.server).to(equal("testserver"))
                        expect(requestData?.publicKey).to(equal("88672ccb97f40bb57238989226cf429b575ba355443f47bc76c5ab144a96c65b"))
                    }
                    
                    it("retrieves recent messages if there was no last message") {
                        mockStorage
                            .read { db in
                                OpenGroupAPI.poll(
                                    db,
                                    server: "testserver",
                                    hasPerformedInitialPoll: false,
                                    timeSinceLastPoll: 0,
                                    using: dependencies
                                )
                            }
                            .get { result in pollResponse = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(pollResponse)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(error?.localizedDescription).to(beNil())
                        expect(pollResponse?.keys).to(contain(.roomMessagesRecent("testRoom")))
                    }
                    
                    it("retrieves recent messages if there was a last message and it has not performed the initial poll and the last message was too long ago") {
                        mockStorage.write { db in
                            try OpenGroup
                                .updateAll(db, OpenGroup.Columns.sequenceNumber.set(to: 123))
                        }
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI.poll(
                                    db,
                                    server: "testserver",
                                    hasPerformedInitialPoll: false,
                                    timeSinceLastPoll: (OpenGroupAPI.Poller.maxInactivityPeriod + 1),
                                    using: dependencies
                                )
                            }
                            .get { result in pollResponse = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(pollResponse)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(error?.localizedDescription).to(beNil())
                        expect(pollResponse?.keys).to(contain(.roomMessagesRecent("testRoom")))
                    }
                    
                    it("retrieves recent messages if there was a last message and it has performed an initial poll but it was not too long ago") {
                        mockStorage.write { db in
                            try OpenGroup
                                .updateAll(db, OpenGroup.Columns.sequenceNumber.set(to: 123))
                        }
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI.poll(
                                    db,
                                    server: "testserver",
                                    hasPerformedInitialPoll: false,
                                    timeSinceLastPoll: 0,
                                    using: dependencies
                                )
                            }
                            .get { result in pollResponse = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(pollResponse)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(error?.localizedDescription).to(beNil())
                        expect(pollResponse?.keys).to(contain(.roomMessagesSince("testRoom", seqNo: 123)))
                    }
                    
                    it("retrieves recent messages if there was a last message and there has already been a poll this session") {
                        mockStorage.write { db in
                            try OpenGroup
                                .updateAll(db, OpenGroup.Columns.sequenceNumber.set(to: 123))
                        }

                        mockStorage
                            .read { db in
                                OpenGroupAPI.poll(
                                    db,
                                    server: "testserver",
                                    hasPerformedInitialPoll: true,
                                    timeSinceLastPoll: 0,
                                    using: dependencies
                                )
                            }
                            .get { result in pollResponse = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(pollResponse)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(error?.localizedDescription).to(beNil())
                        expect(pollResponse?.keys).to(contain(.roomMessagesSince("testRoom", seqNo: 123)))
                    }
                    
                    context("when unblinded") {
                        beforeEach {
                            mockStorage.write { db in
                                _ = try Capability.deleteAll(db)
                                try Capability(openGroupServer: "testserver", variant: .sogs, isMissing: false).insert(db)
                            }
                        }
                    
                        it("does not call the inbox and outbox endpoints") {
                            mockStorage
                                .read { db in
                                    OpenGroupAPI.poll(
                                        db,
                                        server: "testserver",
                                        hasPerformedInitialPoll: false,
                                        timeSinceLastPoll: 0,
                                        using: dependencies
                                    )
                                }
                                .get { result in pollResponse = result }
                                .catch { requestError in error = requestError }
                                .retainUntilComplete()
                            
                            expect(pollResponse)
                                .toEventuallyNot(
                                    beNil(),
                                    timeout: .milliseconds(100)
                                )
                            expect(error?.localizedDescription).to(beNil())
                            
                            // Validate the response data
                            expect(pollResponse?.keys).toNot(contain(.inbox))
                            expect(pollResponse?.keys).toNot(contain(.outbox))
                        }
                    }
                    
                    context("when blinded") {
                        beforeEach {
                            class TestApi: TestOnionRequestAPI {
                                override class var mockResponse: Data? {
                                    let responses: [Data] = [
                                        try! JSONEncoder().encode(
                                            OpenGroupAPI.BatchSubResponse(
                                                code: 200,
                                                headers: [:],
                                                body: OpenGroupAPI.Capabilities(capabilities: [], missing: nil),
                                                failedToParseBody: false
                                            )
                                        ),
                                        try! JSONEncoder().encode(
                                            OpenGroupAPI.BatchSubResponse(
                                                code: 200,
                                                headers: [:],
                                                body: try! JSONDecoder().decode(
                                                    OpenGroupAPI.RoomPollInfo.self,
                                                    from: """
                                                    {
                                                        \"token\":\"test\",
                                                        \"active_users\":1,
                                                        \"read\":true,
                                                        \"write\":true,
                                                        \"upload\":true
                                                    }
                                                    """.data(using: .utf8)!
                                                ),
                                                failedToParseBody: false
                                            )
                                        ),
                                        try! JSONEncoder().encode(
                                            OpenGroupAPI.BatchSubResponse(
                                                code: 200,
                                                headers: [:],
                                                body: [OpenGroupAPI.Message](),
                                                failedToParseBody: false
                                            )
                                        ),
                                        try! JSONEncoder().encode(
                                            OpenGroupAPI.BatchSubResponse(
                                                code: 200,
                                                headers: [:],
                                                body: [OpenGroupAPI.DirectMessage](),
                                                failedToParseBody: false
                                            )
                                        ),
                                        try! JSONEncoder().encode(
                                            OpenGroupAPI.BatchSubResponse(
                                                code: 200,
                                                headers: [:],
                                                body: [OpenGroupAPI.DirectMessage](),
                                                failedToParseBody: false
                                            )
                                        )
                                    ]
                                    
                                    return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
                                }
                            }
                            
                            dependencies = dependencies.with(onionApi: TestApi.self)
                            
                            mockStorage.write { db in
                                _ = try Capability.deleteAll(db)
                                try Capability(openGroupServer: "testserver", variant: .sogs, isMissing: false).insert(db)
                                try Capability(openGroupServer: "testserver", variant: .blind, isMissing: false).insert(db)
                            }
                        }
                    
                        it("includes the inbox and outbox endpoints") {
                            mockStorage
                                .read { db in
                                    OpenGroupAPI.poll(
                                        db,
                                        server: "testserver",
                                        hasPerformedInitialPoll: false,
                                        timeSinceLastPoll: 0,
                                        using: dependencies
                                    )
                                }
                                .get { result in pollResponse = result }
                                .catch { requestError in error = requestError }
                                .retainUntilComplete()
                            
                            expect(pollResponse)
                                .toEventuallyNot(
                                    beNil(),
                                    timeout: .milliseconds(100)
                                )
                            expect(error?.localizedDescription).to(beNil())
                            
                            // Validate the response data
                            expect(pollResponse?.keys).to(contain(.inbox))
                            expect(pollResponse?.keys).to(contain(.outbox))
                        }
                        
                        it("retrieves recent inbox messages if there was no last message") {
                            mockStorage
                                .read { db in
                                    OpenGroupAPI.poll(
                                        db,
                                        server: "testserver",
                                        hasPerformedInitialPoll: true,
                                        timeSinceLastPoll: 0,
                                        using: dependencies
                                    )
                                }
                                .get { result in pollResponse = result }
                                .catch { requestError in error = requestError }
                                .retainUntilComplete()
                            
                            expect(pollResponse)
                                .toEventuallyNot(
                                    beNil(),
                                    timeout: .milliseconds(100)
                                )
                            expect(error?.localizedDescription).to(beNil())
                            expect(pollResponse?.keys).to(contain(.inbox))
                        }
                        
                        it("retrieves inbox messages since the last message if there was one") {
                            mockStorage.write { db in
                                try OpenGroup
                                    .updateAll(db, OpenGroup.Columns.inboxLatestMessageId.set(to: 124))
                            }
                            
                            mockStorage
                                .read { db in
                                    OpenGroupAPI.poll(
                                        db,
                                        server: "testserver",
                                        hasPerformedInitialPoll: true,
                                        timeSinceLastPoll: 0,
                                        using: dependencies
                                    )
                                }
                                .get { result in pollResponse = result }
                                .catch { requestError in error = requestError }
                                .retainUntilComplete()
                            
                            expect(pollResponse)
                                .toEventuallyNot(
                                    beNil(),
                                    timeout: .milliseconds(100)
                                )
                            expect(error?.localizedDescription).to(beNil())
                            expect(pollResponse?.keys).to(contain(.inboxSince(id: 124)))
                        }
                        
                        it("retrieves recent outbox messages if there was no last message") {
                            mockStorage
                                .read { db in
                                    OpenGroupAPI.poll(
                                        db,
                                        server: "testserver",
                                        hasPerformedInitialPoll: true,
                                        timeSinceLastPoll: 0,
                                        using: dependencies
                                    )
                                }
                                .get { result in pollResponse = result }
                                .catch { requestError in error = requestError }
                                .retainUntilComplete()
                            
                            expect(pollResponse)
                                .toEventuallyNot(
                                    beNil(),
                                    timeout: .milliseconds(100)
                                )
                            expect(error?.localizedDescription).to(beNil())
                            expect(pollResponse?.keys).to(contain(.outbox))
                        }
                        
                        it("retrieves outbox messages since the last message if there was one") {
                            mockStorage.write { db in
                                try OpenGroup
                                    .updateAll(db, OpenGroup.Columns.outboxLatestMessageId.set(to: 125))
                            }
                            
                            mockStorage
                                .read { db in
                                    OpenGroupAPI.poll(
                                        db,
                                        server: "testserver",
                                        hasPerformedInitialPoll: true,
                                        timeSinceLastPoll: 0,
                                        using: dependencies
                                    )
                                }
                                .get { result in pollResponse = result }
                                .catch { requestError in error = requestError }
                                .retainUntilComplete()
                            
                            expect(pollResponse)
                                .toEventuallyNot(
                                    beNil(),
                                    timeout: .milliseconds(100)
                                )
                            expect(error?.localizedDescription).to(beNil())
                            expect(pollResponse?.keys).to(contain(.outboxSince(id: 125)))
                        }
                    }
                }
                
                context("and given an invalid response") {
                    it("succeeds but flags the bodies it failed to parse when an unexpected response is returned") {
                        class TestApi: TestOnionRequestAPI {
                            override class var mockResponse: Data? {
                                let responses: [Data] = [
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: OpenGroupAPI.Capabilities(capabilities: [], missing: nil),
                                            failedToParseBody: false
                                        )
                                    ),
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: OpenGroupAPI.PinnedMessage(id: 1, pinnedAt: 1, pinnedBy: ""),
                                            failedToParseBody: false
                                        )
                                    ),
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: OpenGroupAPI.PinnedMessage(id: 1, pinnedAt: 1, pinnedBy: ""),
                                            failedToParseBody: false
                                        )
                                    )
                                ]
                                
                                return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
                            }
                        }
                        dependencies = dependencies.with(onionApi: TestApi.self)
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI.poll(
                                    db,
                                    server: "testserver",
                                    hasPerformedInitialPoll: false,
                                    timeSinceLastPoll: 0,
                                    using: dependencies
                                )
                            }
                            .get { result in pollResponse = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(pollResponse)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(error?.localizedDescription).to(beNil())
                        
                        let capabilitiesResponse: OpenGroupAPI.BatchSubResponse<OpenGroupAPI.Capabilities>? = (pollResponse?[.capabilities]?.1 as? OpenGroupAPI.BatchSubResponse<OpenGroupAPI.Capabilities>)
                        let pollInfoResponse: OpenGroupAPI.BatchSubResponse<OpenGroupAPI.RoomPollInfo>? = (pollResponse?[.roomPollInfo("testRoom", 0)]?.1 as? OpenGroupAPI.BatchSubResponse<OpenGroupAPI.RoomPollInfo>)
                        let messagesResponse: OpenGroupAPI.BatchSubResponse<[Failable<OpenGroupAPI.Message>]>? = (pollResponse?[.roomMessagesRecent("testRoom")]?.1 as? OpenGroupAPI.BatchSubResponse<[Failable<OpenGroupAPI.Message>]>)
                        expect(capabilitiesResponse?.failedToParseBody).to(beFalse())
                        expect(pollInfoResponse?.failedToParseBody).to(beTrue())
                        expect(messagesResponse?.failedToParseBody).to(beTrue())
                    }
                    
                    it("errors when no data is returned") {
                        mockStorage
                            .read { db in
                                OpenGroupAPI.poll(
                                    db,
                                    server: "testserver",
                                    hasPerformedInitialPoll: false,
                                    timeSinceLastPoll: 0,
                                    using: dependencies
                                )
                            }
                            .get { result in pollResponse = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(HTTP.Error.parsingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(pollResponse).to(beNil())
                    }
                    
                    it("errors when invalid data is returned") {
                        class TestApi: TestOnionRequestAPI {
                            override class var mockResponse: Data? { return Data() }
                        }
                        dependencies = dependencies.with(onionApi: TestApi.self)
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI.poll(
                                    db,
                                    server: "testserver",
                                    hasPerformedInitialPoll: false,
                                    timeSinceLastPoll: 0,
                                    using: dependencies
                                )
                            }
                            .get { result in pollResponse = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(HTTP.Error.parsingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(pollResponse).to(beNil())
                    }
                    
                    it("errors when an empty array is returned") {
                        class TestApi: TestOnionRequestAPI {
                            override class var mockResponse: Data? { return "[]".data(using: .utf8) }
                        }
                        dependencies = dependencies.with(onionApi: TestApi.self)
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI.poll(
                                    db,
                                    server: "testserver",
                                    hasPerformedInitialPoll: false,
                                    timeSinceLastPoll: 0,
                                    using: dependencies
                                )
                            }
                            .get { result in pollResponse = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(HTTP.Error.parsingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(pollResponse).to(beNil())
                    }
                    
                    it("errors when an empty object is returned") {
                        class TestApi: TestOnionRequestAPI {
                            override class var mockResponse: Data? { return "{}".data(using: .utf8) }
                        }
                        dependencies = dependencies.with(onionApi: TestApi.self)
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI.poll(
                                    db,
                                    server: "testserver",
                                    hasPerformedInitialPoll: false,
                                    timeSinceLastPoll: 0,
                                    using: dependencies
                                )
                            }
                            .get { result in pollResponse = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(HTTP.Error.parsingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(pollResponse).to(beNil())
                    }
                    
                    it("errors when a different number of responses are returned") {
                        class TestApi: TestOnionRequestAPI {
                            override class var mockResponse: Data? {
                                let responses: [Data] = [
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: OpenGroupAPI.Capabilities(capabilities: [], missing: nil),
                                            failedToParseBody: false
                                        )
                                    ),
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: try! JSONDecoder().decode(
                                                OpenGroupAPI.RoomPollInfo.self,
                                                from: """
                                                {
                                                    \"token\":\"test\",
                                                    \"active_users\":1,
                                                    \"read\":true,
                                                    \"write\":true,
                                                    \"upload\":true
                                                }
                                                """.data(using: .utf8)!
                                            ),
                                            failedToParseBody: false
                                        )
                                    )
                                ]
                                
                                return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
                            }
                        }
                        dependencies = dependencies.with(onionApi: TestApi.self)
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI.poll(
                                    db,
                                    server: "testserver",
                                    hasPerformedInitialPoll: false,
                                    timeSinceLastPoll: 0,
                                    using: dependencies
                                )
                            }
                            .get { result in pollResponse = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(HTTP.Error.parsingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(pollResponse).to(beNil())
                    }
                }
            }
            
            // MARK: - Capabilities
            
            context("when doing a capabilities request") {
                it("generates the request and handles the response correctly") {
                    class TestApi: TestOnionRequestAPI {
                        static let data: OpenGroupAPI.Capabilities = OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: nil)
                        
                        override class var mockResponse: Data? { try! JSONEncoder().encode(data) }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                    
                    var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Capabilities)?
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI.capabilities(
                                db,
                                server: "testserver",
                                using: dependencies
                            )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate the response data
                    expect(response?.data).to(equal(TestApi.data))
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("GET"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/capabilities"))
                }
            }
            
            // MARK: - Rooms
            
            context("when doing a rooms request") {
                it("generates the request and handles the response correctly") {
                    class TestApi: TestOnionRequestAPI {
                        static let data: [OpenGroupAPI.Room] = [
                            OpenGroupAPI.Room(
                                token: "test",
                                name: "test",
                                roomDescription: nil,
                                infoUpdates: 0,
                                messageSequence: 0,
                                created: 0,
                                activeUsers: 0,
                                activeUsersCutoff: 0,
                                imageId: nil,
                                pinnedMessages: nil,
                                admin: false,
                                globalAdmin: false,
                                admins: [],
                                hiddenAdmins: nil,
                                moderator: false,
                                globalModerator: false,
                                moderators: [],
                                hiddenModerators: nil,
                                read: false,
                                defaultRead: nil,
                                defaultAccessible: nil,
                                write: false,
                                defaultWrite: nil,
                                upload: false,
                                defaultUpload: nil
                            )
                        ]
                        
                        override class var mockResponse: Data? { return try! JSONEncoder().encode(data) }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                    
                    var response: (info: OnionRequestResponseInfoType, data: [OpenGroupAPI.Room])?
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI.rooms(
                                db,
                                server: "testserver",
                                using: dependencies
                            )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate the response data
                    expect(response?.data).to(equal(TestApi.data))
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("GET"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/rooms"))
                }
            }
            
            // MARK: - CapabilitiesAndRoom
            
            context("when doing a capabilitiesAndRoom request") {
                context("and given a correct response") {
                    it("generates the request and handles the response correctly") {
                        class TestApi: TestOnionRequestAPI {
                            static let capabilitiesData: OpenGroupAPI.Capabilities = OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: nil)
                            static let roomData: OpenGroupAPI.Room = OpenGroupAPI.Room(
                                token: "test",
                                name: "test",
                                roomDescription: nil,
                                infoUpdates: 0,
                                messageSequence: 0,
                                created: 0,
                                activeUsers: 0,
                                activeUsersCutoff: 0,
                                imageId: nil,
                                pinnedMessages: nil,
                                admin: false,
                                globalAdmin: false,
                                admins: [],
                                hiddenAdmins: nil,
                                moderator: false,
                                globalModerator: false,
                                moderators: [],
                                hiddenModerators: nil,
                                read: false,
                                defaultRead: nil,
                                defaultAccessible: nil,
                                write: false,
                                defaultWrite: nil,
                                upload: false,
                                defaultUpload: nil
                            )
                            
                            override class var mockResponse: Data? {
                                let responses: [Data] = [
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: capabilitiesData,
                                            failedToParseBody: false
                                        )
                                    ),
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: roomData,
                                            failedToParseBody: false
                                        )
                                    )
                                ]
                                
                                return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
                            }
                        }
                        dependencies = dependencies.with(onionApi: TestApi.self)
                        
                        var response: (capabilities: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Capabilities?), room: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Room?))?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI.capabilitiesAndRoom(
                                    db,
                                    for: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(response)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(error?.localizedDescription).to(beNil())
                        
                        // Validate the response data
                        expect(response?.capabilities.data).to(equal(TestApi.capabilitiesData))
                        expect(response?.room.data).to(equal(TestApi.roomData))
                        
                        // Validate request data
                        let requestData: TestOnionRequestAPI.RequestData? = (response?.capabilities.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                        expect(requestData?.httpMethod).to(equal("POST"))
                        expect(requestData?.server).to(equal("testserver"))
                        expect(requestData?.urlString).to(equal("testserver/sequence"))
                    }
                }
                
                context("and given an invalid response") {
                    it("errors when only a capabilities response is returned") {
                        class TestApi: TestOnionRequestAPI {
                            static let capabilitiesData: OpenGroupAPI.Capabilities = OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: nil)
                            
                            override class var mockResponse: Data? {
                                let responses: [Data] = [
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: capabilitiesData,
                                            failedToParseBody: false
                                        )
                                    )
                                ]
                                
                                return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
                            }
                        }
                        dependencies = dependencies.with(onionApi: TestApi.self)
                        
                        var response: (capabilities: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Capabilities?), room: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Room?))?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .capabilitiesAndRoom(
                                        db,
                                        for: "testRoom",
                                        on: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(HTTP.Error.parsingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                    
                    it("errors when only a room response is returned") {
                        class TestApi: TestOnionRequestAPI {
                            static let roomData: OpenGroupAPI.Room = OpenGroupAPI.Room(
                                token: "test",
                                name: "test",
                                roomDescription: nil,
                                infoUpdates: 0,
                                messageSequence: 0,
                                created: 0,
                                activeUsers: 0,
                                activeUsersCutoff: 0,
                                imageId: nil,
                                pinnedMessages: nil,
                                admin: false,
                                globalAdmin: false,
                                admins: [],
                                hiddenAdmins: nil,
                                moderator: false,
                                globalModerator: false,
                                moderators: [],
                                hiddenModerators: nil,
                                read: false,
                                defaultRead: nil,
                                defaultAccessible: nil,
                                write: false,
                                defaultWrite: nil,
                                upload: false,
                                defaultUpload: nil
                            )
                            
                            override class var mockResponse: Data? {
                                let responses: [Data] = [
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: roomData,
                                            failedToParseBody: false
                                        )
                                    )
                                ]
                                
                                return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
                            }
                        }
                        dependencies = dependencies.with(onionApi: TestApi.self)
                        
                        var response: (capabilities: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Capabilities?), room: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Room?))?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .capabilitiesAndRoom(
                                        db,
                                        for: "testRoom",
                                        on: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(HTTP.Error.parsingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                    
                    it("errors when an extra response is returned") {
                        class TestApi: TestOnionRequestAPI {
                            static let capabilitiesData: OpenGroupAPI.Capabilities = OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: nil)
                            static let roomData: OpenGroupAPI.Room = OpenGroupAPI.Room(
                                token: "test",
                                name: "test",
                                roomDescription: nil,
                                infoUpdates: 0,
                                messageSequence: 0,
                                created: 0,
                                activeUsers: 0,
                                activeUsersCutoff: 0,
                                imageId: nil,
                                pinnedMessages: nil,
                                admin: false,
                                globalAdmin: false,
                                admins: [],
                                hiddenAdmins: nil,
                                moderator: false,
                                globalModerator: false,
                                moderators: [],
                                hiddenModerators: nil,
                                read: false,
                                defaultRead: nil,
                                defaultAccessible: nil,
                                write: false,
                                defaultWrite: nil,
                                upload: false,
                                defaultUpload: nil
                            )
                            
                            override class var mockResponse: Data? {
                                let responses: [Data] = [
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: capabilitiesData,
                                            failedToParseBody: false
                                        )
                                    ),
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: roomData,
                                            failedToParseBody: false
                                        )
                                    ),
                                    try! JSONEncoder().encode(
                                        OpenGroupAPI.BatchSubResponse(
                                            code: 200,
                                            headers: [:],
                                            body: OpenGroupAPI.PinnedMessage(id: 1, pinnedAt: 1, pinnedBy: ""),
                                            failedToParseBody: false
                                        )
                                    )
                                ]
                                
                                return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
                            }
                        }
                        dependencies = dependencies.with(onionApi: TestApi.self)
                        
                        var response: (capabilities: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Capabilities?), room: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Room?))?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI.capabilitiesAndRoom(
                                    db,
                                    for: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(HTTP.Error.parsingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                }
            }
            
            // MARK: - Messages
            
            context("when sending messages") {
                var messageData: OpenGroupAPI.Message!
                
                beforeEach {
                    class TestApi: TestOnionRequestAPI {
                        static let data: OpenGroupAPI.Message = OpenGroupAPI.Message(
                            id: 126,
                            sender: "testSender",
                            posted: 321,
                            edited: nil,
                            deleted: nil,
                            seqNo: 10,
                            whisper: false,
                            whisperMods: false,
                            whisperTo: nil,
                            base64EncodedData: nil,
                            base64EncodedSignature: nil,
                            reactions: nil
                        )
                        
                        override class var mockResponse: Data? { return try! JSONEncoder().encode(data) }
                    }
                    messageData = TestApi.data
                    dependencies = dependencies.with(onionApi: TestApi.self)
                }
                
                afterEach {
                    messageData = nil
                }
                
                it("correctly sends the message") {
                    var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .send(
                                    db,
                                    plaintext: "test".data(using: .utf8)!,
                                    to: "testRoom",
                                    on: "testServer",
                                    whisperTo: nil,
                                    whisperMods: false,
                                    fileIds: nil,
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate the response data
                    expect(response?.data).to(equal(messageData))
                    
                    // Validate signature headers
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/room/testRoom/message"))
                }
                
                context("when unblinded") {
                    beforeEach {
                        mockStorage.write { db in
                            _ = try Capability.deleteAll(db)
                            try Capability(openGroupServer: "testserver", variant: .sogs, isMissing: false).insert(db)
                        }
                    }
                    
                    it("signs the message correctly") {
                        var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .send(
                                        db,
                                        plaintext: "test".data(using: .utf8)!,
                                        to: "testRoom",
                                        on: "testServer",
                                        whisperTo: nil,
                                        whisperMods: false,
                                        fileIds: nil,
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(response)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(error?.localizedDescription).to(beNil())
                        
                        // Validate request body
                        let requestData: TestOnionRequestAPI.RequestData? = (response?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                        let requestBody: OpenGroupAPI.SendMessageRequest = try! JSONDecoder().decode(OpenGroupAPI.SendMessageRequest.self, from: requestData!.body!)
                        
                        expect(requestBody.data).to(equal("test".data(using: .utf8)))
                        expect(requestBody.signature).to(equal("TestStandardSignature".data(using: .utf8)))
                    }
                    
                    it("fails to sign if there is no open group") {
                        mockStorage.write { db in
                            _ = try OpenGroup.deleteAll(db)
                        }
                        
                        var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .send(
                                        db,
                                        plaintext: "test".data(using: .utf8)!,
                                        to: "testRoom",
                                        on: "testserver",
                                        whisperTo: nil,
                                        whisperMods: false,
                                        fileIds: nil,
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                    
                    it("fails to sign if there is no user key pair") {
                        mockStorage.write { db in
                            _ = try Identity.filter(id: .x25519PublicKey).deleteAll(db)
                            _ = try Identity.filter(id: .x25519PrivateKey).deleteAll(db)
                        }
                        
                        var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .send(
                                        db,
                                        plaintext: "test".data(using: .utf8)!,
                                        to: "testRoom",
                                        on: "testserver",
                                        whisperTo: nil,
                                        whisperMods: false,
                                        fileIds: nil,
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                    
                    it("fails to sign if no signature is generated") {
                        mockEd25519.reset() // The 'keyPair' value doesn't equate so have to explicitly reset
                        mockEd25519.when { try $0.sign(data: anyArray(), keyPair: any()) }.thenReturn(nil)
                        
                        var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .send(
                                        db,
                                        plaintext: "test".data(using: .utf8)!,
                                        to: "testRoom",
                                        on: "testserver",
                                        whisperTo: nil,
                                        whisperMods: false,
                                        fileIds: nil,
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                }
                
                context("when blinded") {
                    beforeEach {
                        mockStorage.write { db in
                            _ = try Capability.deleteAll(db)
                            try Capability(openGroupServer: "testserver", variant: .sogs, isMissing: false).insert(db)
                            try Capability(openGroupServer: "testserver", variant: .blind, isMissing: false).insert(db)
                        }
                    }
                    
                    it("signs the message correctly") {
                        var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .send(
                                        db,
                                        plaintext: "test".data(using: .utf8)!,
                                        to: "testRoom",
                                        on: "testserver",
                                        whisperTo: nil,
                                        whisperMods: false,
                                        fileIds: nil,
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(response)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(error?.localizedDescription).to(beNil())
                        
                        // Validate request body
                        let requestData: TestOnionRequestAPI.RequestData? = (response?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                        let requestBody: OpenGroupAPI.SendMessageRequest = try! JSONDecoder().decode(OpenGroupAPI.SendMessageRequest.self, from: requestData!.body!)
                        
                        expect(requestBody.data).to(equal("test".data(using: .utf8)))
                        expect(requestBody.signature).to(equal("TestSogsSignature".data(using: .utf8)))
                    }
                    
                    it("fails to sign if there is no open group") {
                        mockStorage.write { db in
                            _ = try OpenGroup.deleteAll(db)
                        }
                        
                        var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .send(
                                        db,
                                        plaintext: "test".data(using: .utf8)!,
                                        to: "testRoom",
                                        on: "testServer",
                                        whisperTo: nil,
                                        whisperMods: false,
                                        fileIds: nil,
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                    
                    it("fails to sign if there is no ed key pair key") {
                        mockStorage.write { db in
                            _ = try Identity.filter(id: .ed25519PublicKey).deleteAll(db)
                            _ = try Identity.filter(id: .ed25519SecretKey).deleteAll(db)
                        }
                        
                        var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .send(
                                        db,
                                        plaintext: "test".data(using: .utf8)!,
                                        to: "testRoom",
                                        on: "testserver",
                                        whisperTo: nil,
                                        whisperMods: false,
                                        fileIds: nil,
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                    
                    it("fails to sign if no signature is generated") {
                        mockSodium
                            .when {
                                $0.sogsSignature(
                                    message: anyArray(),
                                    secretKey: anyArray(),
                                    blindedSecretKey: anyArray(),
                                    blindedPublicKey: anyArray()
                                )
                            }
                            .thenReturn(nil)
                        
                        var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .send(
                                        db,
                                        plaintext: "test".data(using: .utf8)!,
                                        to: "testRoom",
                                        on: "testserver",
                                        whisperTo: nil,
                                        whisperMods: false,
                                        fileIds: nil,
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                }
            }
            
            context("when getting an individual message") {
                it("generates the request and handles the response correctly") {
                    class TestApi: TestOnionRequestAPI {
                        static let data: OpenGroupAPI.Message = OpenGroupAPI.Message(
                            id: 126,
                            sender: "testSender",
                            posted: 321,
                            edited: nil,
                            deleted: nil,
                            seqNo: 10,
                            whisper: false,
                            whisperMods: false,
                            whisperTo: nil,
                            base64EncodedData: nil,
                            base64EncodedSignature: nil,
                            reactions: nil
                        )
                        
                        override class var mockResponse: Data? { return try! JSONEncoder().encode(data) }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                    
                    var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .message(
                                    db,
                                    id: 123,
                                    in: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate the response data
                    expect(response?.data).to(equal(TestApi.data))
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("GET"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/room/testRoom/message/123"))
                }
            }
            
            context("when updating a message") {
                beforeEach {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                    
                    mockStorage.write { db in
                        _ = try Identity
                            .filter(id: .ed25519PublicKey)
                            .updateAll(db, Identity.Columns.data.set(to: Data()))
                        _ = try Identity
                            .filter(id: .ed25519SecretKey)
                            .updateAll(db, Identity.Columns.data.set(to: Data()))
                    }
                }
                
                it("correctly sends the update") {
                    var response: (info: OnionRequestResponseInfoType, data: Data?)?
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .messageUpdate(
                                    db,
                                    id: 123,
                                    plaintext: "test".data(using: .utf8)!,
                                    fileIds: nil,
                                    in: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate signature headers
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("PUT"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/room/testRoom/message/123"))
                }
                
                context("when unblinded") {
                    beforeEach {
                        mockStorage.write { db in
                            _ = try Capability.deleteAll(db)
                            try Capability(openGroupServer: "testserver", variant: .sogs, isMissing: false).insert(db)
                        }
                    }
                    
                    it("signs the message correctly") {
                        var response: (info: OnionRequestResponseInfoType, data: Data?)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .messageUpdate(
                                        db,
                                        id: 123,
                                        plaintext: "test".data(using: .utf8)!,
                                        fileIds: nil,
                                        in: "testRoom",
                                        on: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(response)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(error?.localizedDescription).to(beNil())
                        
                        // Validate request body
                        let requestData: TestOnionRequestAPI.RequestData? = (response?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                        let requestBody: OpenGroupAPI.UpdateMessageRequest = try! JSONDecoder().decode(OpenGroupAPI.UpdateMessageRequest.self, from: requestData!.body!)
                        
                        expect(requestBody.data).to(equal("test".data(using: .utf8)))
                        expect(requestBody.signature).to(equal("TestStandardSignature".data(using: .utf8)))
                    }
                    
                    it("fails to sign if there is no open group") {
                        mockStorage.write { db in
                            _ = try OpenGroup.deleteAll(db)
                        }
                        
                        var response: (info: OnionRequestResponseInfoType, data: Data?)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .messageUpdate(
                                        db,
                                        id: 123,
                                        plaintext: "test".data(using: .utf8)!,
                                        fileIds: nil,
                                        in: "testRoom",
                                        on: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                    
                    it("fails to sign if there is no user key pair") {
                        mockStorage.write { db in
                            _ = try Identity.filter(id: .x25519PublicKey).deleteAll(db)
                            _ = try Identity.filter(id: .x25519PrivateKey).deleteAll(db)
                        }
                        
                        var response: (info: OnionRequestResponseInfoType, data: Data?)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .messageUpdate(
                                        db,
                                        id: 123,
                                        plaintext: "test".data(using: .utf8)!,
                                        fileIds: nil,
                                        in: "testRoom",
                                        on: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                    
                    it("fails to sign if no signature is generated") {
                        mockEd25519.reset() // The 'keyPair' value doesn't equate so have to explicitly reset
                        mockEd25519.when { try $0.sign(data: anyArray(), keyPair: any()) }.thenReturn(nil)
                        
                        var response: (info: OnionRequestResponseInfoType, data: Data?)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .messageUpdate(
                                        db,
                                        id: 123,
                                        plaintext: "test".data(using: .utf8)!,
                                        fileIds: nil,
                                        in: "testRoom",
                                        on: "testServer",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                }
                
                context("when blinded") {
                    beforeEach {
                        mockStorage.write { db in
                            _ = try Capability.deleteAll(db)
                            try Capability(openGroupServer: "testserver", variant: .sogs, isMissing: false).insert(db)
                            try Capability(openGroupServer: "testserver", variant: .blind, isMissing: false).insert(db)
                        }
                    }
                    
                    it("signs the message correctly") {
                        var response: (info: OnionRequestResponseInfoType, data: Data?)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .messageUpdate(
                                        db,
                                        id: 123,
                                        plaintext: "test".data(using: .utf8)!,
                                        fileIds: nil,
                                        in: "testRoom",
                                        on: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(response)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(error?.localizedDescription).to(beNil())
                        
                        // Validate request body
                        let requestData: TestOnionRequestAPI.RequestData? = (response?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                        let requestBody: OpenGroupAPI.UpdateMessageRequest = try! JSONDecoder().decode(OpenGroupAPI.UpdateMessageRequest.self, from: requestData!.body!)
                        
                        expect(requestBody.data).to(equal("test".data(using: .utf8)))
                        expect(requestBody.signature).to(equal("TestSogsSignature".data(using: .utf8)))
                    }
                    
                    it("fails to sign if there is no open group") {
                        mockStorage.write { db in
                            _ = try OpenGroup.deleteAll(db)
                        }
                        
                        var response: (info: OnionRequestResponseInfoType, data: Data?)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .messageUpdate(
                                        db,
                                        id: 123,
                                        plaintext: "test".data(using: .utf8)!,
                                        fileIds: nil,
                                        in: "testRoom",
                                        on: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                    
                    it("fails to sign if there is no ed key pair key") {
                        mockStorage.write { db in
                            _ = try Identity.filter(id: .ed25519PublicKey).deleteAll(db)
                            _ = try Identity.filter(id: .ed25519SecretKey).deleteAll(db)
                        }
                        
                        var response: (info: OnionRequestResponseInfoType, data: Data?)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .messageUpdate(
                                        db,
                                        id: 123,
                                        plaintext: "test".data(using: .utf8)!,
                                        fileIds: nil,
                                        in: "testRoom",
                                        on: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                    
                    it("fails to sign if no signature is generated") {
                        mockSodium
                            .when {
                                $0.sogsSignature(
                                    message: anyArray(),
                                    secretKey: anyArray(),
                                    blindedSecretKey: anyArray(),
                                    blindedPublicKey: anyArray()
                                )
                            }
                            .thenReturn(nil)
                        
                        var response: (info: OnionRequestResponseInfoType, data: Data?)?
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .messageUpdate(
                                        db,
                                        id: 123,
                                        plaintext: "test".data(using: .utf8)!,
                                        fileIds: nil,
                                        in: "testRoom",
                                        on: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                }
            }
            
            context("when deleting a message") {
                it("generates the request and handles the response correctly") {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                    
                    var response: (info: OnionRequestResponseInfoType, data: Data?)?
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .messageDelete(
                                    db,
                                    id: 123,
                                    in: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("DELETE"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/room/testRoom/message/123"))
                }
            }
            
            context("when deleting all messages for a user") {
                var response: (info: OnionRequestResponseInfoType, data: Data?)?
                
                beforeEach {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                }
                
                afterEach {
                    response = nil
                }
                
                it("generates the request and handles the response correctly") {
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .messagesDeleteAll(
                                    db,
                                    sessionId: "testUserId",
                                    in: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("DELETE"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/room/testRoom/all/testUserId"))
                }
            }
            
            // MARK: - Pinning
            
            context("when pinning a message") {
                it("generates the request and handles the response correctly") {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                    
                    var response: OnionRequestResponseInfoType?
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .pinMessage(
                                    db,
                                    id: 123,
                                    in: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/room/testRoom/pin/123"))
                }
            }
            
            context("when unpinning a message") {
                it("generates the request and handles the response correctly") {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                    
                    var response: OnionRequestResponseInfoType?
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .unpinMessage(
                                    db,
                                    id: 123,
                                    in: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/room/testRoom/unpin/123"))
                }
            }
            
            context("when unpinning all messages") {
                it("generates the request and handles the response correctly") {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                    
                    var response: OnionRequestResponseInfoType?
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .unpinAll(
                                    db,
                                    in: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/room/testRoom/unpin/all"))
                }
            }
            
            // MARK: - Files
            
            context("when uploading files") {
                it("generates the request and handles the response correctly") {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? {
                            return try! JSONEncoder().encode(FileUploadResponse(id: "1"))
                        }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .uploadFile(
                                    db,
                                    bytes: [],
                                    to: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate signature headers
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/room/testRoom/file"))
                }
                
                it("doesn't add a fileName to the content-disposition header when not provided") {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? {
                            return try! JSONEncoder().encode(FileUploadResponse(id: "1"))
                        }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .uploadFile(
                                    db,
                                    bytes: [],
                                    to: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate signature headers
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.headers[Header.contentDisposition.rawValue])
                        .toNot(contain("filename"))
                }
                
                it("adds the fileName to the content-disposition header when provided") {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? {
                            return try! JSONEncoder().encode(FileUploadResponse(id: "1"))
                        }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .uploadFile(
                                    db,
                                    bytes: [],
                                    fileName: "TestFileName",
                                    to: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate signature headers
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.headers[Header.contentDisposition.rawValue]).to(contain("TestFileName"))
                }
            }
            
            context("when downloading files") {
                it("generates the request and handles the response correctly") {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? {
                            return Data()
                        }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .downloadFile(
                                    db,
                                    fileId: "1",
                                    from: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate signature headers
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("GET"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/room/testRoom/file/1"))
                }
            }
            
            // MARK: - Inbox/Outbox (Message Requests)
            
            context("when sending message requests") {
                var messageData: OpenGroupAPI.SendDirectMessageResponse!
                
                beforeEach {
                    class TestApi: TestOnionRequestAPI {
                        static let data: OpenGroupAPI.SendDirectMessageResponse = OpenGroupAPI.SendDirectMessageResponse(
                            id: 126,
                            sender: "testSender",
                            recipient: "testRecipient",
                            posted: 321,
                            expires: 456
                        )
                        
                        override class var mockResponse: Data? { return try! JSONEncoder().encode(data) }
                    }
                    messageData = TestApi.data
                    dependencies = dependencies.with(onionApi: TestApi.self)
                }
                
                afterEach {
                    messageData = nil
                }
                
                it("correctly sends the message request") {
                    var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.SendDirectMessageResponse)?
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .send(
                                    db,
                                    ciphertext: "test".data(using: .utf8)!,
                                    toInboxFor: "testUserId",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate the response data
                    expect(response?.data).to(equal(messageData))
                    
                    // Validate signature headers
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/inbox/testUserId"))
                }
            }
            
            // MARK: - Users
            
            context("when banning a user") {
                var response: (info: OnionRequestResponseInfoType, data: Data?)?
                
                beforeEach {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                }
                
                afterEach {
                    response = nil
                }
                
                it("generates the request and handles the response correctly") {
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .userBan(
                                    db,
                                    sessionId: "testUserId",
                                    for: nil,
                                    from: nil,
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/user/testUserId/ban"))
                }
                
                it("does a global ban if no room tokens are provided") {
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .userBan(
                                    db,
                                    sessionId: "testUserId",
                                    for: nil,
                                    from: nil,
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserBanRequest = try! JSONDecoder().decode(OpenGroupAPI.UserBanRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beTrue())
                    expect(requestBody.rooms).to(beNil())
                }
                
                it("does room specific bans if room tokens are provided") {
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .userBan(
                                    db,
                                    sessionId: "testUserId",
                                    for: nil,
                                    from: ["testRoom"],
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserBanRequest = try! JSONDecoder().decode(OpenGroupAPI.UserBanRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beNil())
                    expect(requestBody.rooms).to(equal(["testRoom"]))
                }
            }
            
            context("when unbanning a user") {
                var response: (info: OnionRequestResponseInfoType, data: Data?)?
                
                beforeEach {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                }
                
                afterEach {
                    response = nil
                }
                
                it("generates the request and handles the response correctly") {
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .userUnban(
                                    db,
                                    sessionId: "testUserId",
                                    from: nil,
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/user/testUserId/unban"))
                }
                
                it("does a global ban if no room tokens are provided") {
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .userUnban(
                                    db,
                                    sessionId: "testUserId",
                                    from: nil,
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserUnbanRequest = try! JSONDecoder().decode(OpenGroupAPI.UserUnbanRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beTrue())
                    expect(requestBody.rooms).to(beNil())
                }
                
                it("does room specific bans if room tokens are provided") {
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .userUnban(
                                    db,
                                    sessionId: "testUserId",
                                    from: ["testRoom"],
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserUnbanRequest = try! JSONDecoder().decode(OpenGroupAPI.UserUnbanRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beNil())
                    expect(requestBody.rooms).to(equal(["testRoom"]))
                }
            }
            
            context("when updating a users permissions") {
                var response: (info: OnionRequestResponseInfoType, data: Data?)?
                
                beforeEach {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                }
                
                afterEach {
                    response = nil
                }
                
                it("generates the request and handles the response correctly") {
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .userModeratorUpdate(
                                    db,
                                    sessionId: "testUserId",
                                    moderator: true,
                                    admin: nil,
                                    visible: true,
                                    for: nil,
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/user/testUserId/moderator"))
                }
                
                it("does a global update if no room tokens are provided") {
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .userModeratorUpdate(
                                    db,
                                    sessionId: "testUserId",
                                    moderator: true,
                                    admin: nil,
                                    visible: true,
                                    for: nil,
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserModeratorRequest = try! JSONDecoder().decode(OpenGroupAPI.UserModeratorRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beTrue())
                    expect(requestBody.rooms).to(beNil())
                }
                
                it("does room specific updates if room tokens are provided") {
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .userModeratorUpdate(
                                    db,
                                    sessionId: "testUserId",
                                    moderator: true,
                                    admin: nil,
                                    visible: true,
                                    for: ["testRoom"],
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.info as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserModeratorRequest = try! JSONDecoder().decode(OpenGroupAPI.UserModeratorRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beNil())
                    expect(requestBody.rooms).to(equal(["testRoom"]))
                }
                
                it("fails if neither moderator or admin are set") {
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .userModeratorUpdate(
                                    db,
                                    sessionId: "testUserId",
                                    moderator: nil,
                                    admin: nil,
                                    visible: true,
                                    for: nil,
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(error?.localizedDescription)
                        .toEventually(
                            equal(HTTP.Error.generic.localizedDescription),
                            timeout: .milliseconds(100)
                        )
                    
                    expect(response).to(beNil())
                }
            }
            
            context("when banning and deleting all messages for a user") {
                var response: [OnionRequestResponseInfoType]?
                
                beforeEach {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? {
                            let responses: [Data] = [
                                try! JSONEncoder().encode(
                                    OpenGroupAPI.BatchSubResponse<NoResponse>(
                                        code: 200,
                                        headers: [:],
                                        body: nil,
                                        failedToParseBody: false
                                    )
                                ),
                                try! JSONEncoder().encode(
                                    OpenGroupAPI.BatchSubResponse<NoResponse>(
                                        code: 200,
                                        headers: [:],
                                        body: nil,
                                        failedToParseBody: false
                                    )
                                )
                            ]
                            
                            return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
                        }
                    }
                    dependencies = dependencies.with(onionApi: TestApi.self)
                }
                
                afterEach {
                    response = nil
                }
                
                it("generates the request and handles the response correctly") {
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .userBanAndDeleteAllMessages(
                                    db,
                                    sessionId: "testUserId",
                                    in: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.first as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testserver"))
                    expect(requestData?.urlString).to(equal("testserver/sequence"))
                }
                
                it("bans the user from the specified room rather than globally") {
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .userBanAndDeleteAllMessages(
                                    db,
                                    sessionId: "testUserId",
                                    in: "testRoom",
                                    on: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    
                    // Validate request data
                    let requestData: TestOnionRequestAPI.RequestData? = (response?.first as? TestOnionRequestAPI.ResponseInfo)?.requestData
                    let jsonObject: Any = try! JSONSerialization.jsonObject(
                        with: requestData!.body!,
                        options: [.fragmentsAllowed]
                    )
                    let firstJsonObject: Any = ((jsonObject as! [Any]).first as! [String: Any])["json"]!
                    let firstJsonData: Data = try! JSONSerialization.data(withJSONObject: firstJsonObject)
                    let firstRequestBody: OpenGroupAPI.UserBanRequest = try! JSONDecoder()
                        .decode(OpenGroupAPI.UserBanRequest.self, from: firstJsonData)
                    
                    expect(firstRequestBody.global).to(beNil())
                    expect(firstRequestBody.rooms).to(equal(["testRoom"]))
                }
            }
            
            // MARK: - Authentication
            
            context("when signing") {
                beforeEach {
                    class TestApi: TestOnionRequestAPI {
                        override class var mockResponse: Data? {
                            return try! JSONEncoder().encode([OpenGroupAPI.Room]())
                        }
                    }
                    
                    dependencies = dependencies.with(onionApi: TestApi.self)
                }
                
                it("fails when there is no userEdKeyPair") {
                    mockStorage.write { db in
                        _ = try Identity.filter(id: .ed25519PublicKey).deleteAll(db)
                        _ = try Identity.filter(id: .ed25519SecretKey).deleteAll(db)
                    }
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .rooms(
                                    db,
                                    server: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(error?.localizedDescription)
                        .toEventually(
                            equal(OpenGroupAPIError.signingFailed.localizedDescription),
                            timeout: .milliseconds(100)
                        )
                    
                    expect(response).to(beNil())
                }
                
                it("fails when there is no serverPublicKey") {
                    mockStorage.write { db in
                        _ = try OpenGroup.deleteAll(db)
                    }
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .rooms(
                                    db,
                                    server: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(error?.localizedDescription)
                        .toEventually(
                            equal(OpenGroupAPIError.noPublicKey.localizedDescription),
                            timeout: .milliseconds(100)
                        )
                    
                    expect(response).to(beNil())
                }
                
                it("fails when the serverPublicKey is not a hex string") {
                    mockStorage.write { db in
                        _ = try OpenGroup.updateAll(db, OpenGroup.Columns.publicKey.set(to: "TestString!!!"))
                    }
                    
                    mockStorage
                        .read { db in
                            OpenGroupAPI
                                .rooms(
                                    db,
                                    server: "testserver",
                                    using: dependencies
                                )
                        }
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(error?.localizedDescription)
                        .toEventually(
                            equal(OpenGroupAPIError.signingFailed.localizedDescription),
                            timeout: .milliseconds(100)
                        )
                    
                    expect(response).to(beNil())
                }
                
                context("when unblinded") {
                    beforeEach {
                        mockStorage.write { db in
                            _ = try Capability.deleteAll(db)
                            try Capability(openGroupServer: "testserver", variant: .sogs, isMissing: false).insert(db)
                        }
                    }
                    
                    it("signs correctly") {
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .rooms(
                                        db,
                                        server: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(response)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(error?.localizedDescription).to(beNil())
                        
                        // Validate signature headers
                        let requestData: TestOnionRequestAPI.RequestData? = (response?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                        expect(requestData?.urlString).to(equal("testserver/rooms"))
                        expect(requestData?.httpMethod).to(equal("GET"))
                        expect(requestData?.server).to(equal("testserver"))
                        expect(requestData?.publicKey).to(equal("88672ccb97f40bb57238989226cf429b575ba355443f47bc76c5ab144a96c65b"))
                        expect(requestData?.headers).to(haveCount(4))
                        expect(requestData?.headers[Header.sogsPubKey.rawValue])
                            .to(equal("00bac6e71efd7dfa4a83c98ed24f254ab2c267f9ccdb172a5280a0444ad24e89cc"))
                        expect(requestData?.headers[Header.sogsTimestamp.rawValue]).to(equal("1234567890"))
                        expect(requestData?.headers[Header.sogsNonce.rawValue]).to(equal("pK6YRtQApl4NhECGizF0Cg=="))
                        expect(requestData?.headers[Header.sogsSignature.rawValue]).to(equal("TestSignature".bytes.toBase64()))
                    }
                    
                    it("fails when the signature is not generated") {
                        mockSign.when { $0.signature(message: anyArray(), secretKey: anyArray()) }.thenReturn(nil)
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .rooms(
                                        db,
                                        server: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                }
                
                context("when blinded") {
                    beforeEach {
                        mockStorage.write { db in
                            _ = try Capability.deleteAll(db)
                            try Capability(openGroupServer: "testserver", variant: .sogs, isMissing: false).insert(db)
                            try Capability(openGroupServer: "testserver", variant: .blind, isMissing: false).insert(db)
                        }
                    }
                    
                    it("signs correctly") {
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .rooms(
                                        db,
                                        server: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(response)
                            .toEventuallyNot(
                                beNil(),
                                timeout: .milliseconds(100)
                            )
                        expect(error?.localizedDescription).to(beNil())
                        
                        // Validate signature headers
                        let requestData: TestOnionRequestAPI.RequestData? = (response?.0 as? TestOnionRequestAPI.ResponseInfo)?.requestData
                        expect(requestData?.urlString).to(equal("testserver/rooms"))
                        expect(requestData?.httpMethod).to(equal("GET"))
                        expect(requestData?.server).to(equal("testserver"))
                        expect(requestData?.publicKey).to(equal("88672ccb97f40bb57238989226cf429b575ba355443f47bc76c5ab144a96c65b"))
                        expect(requestData?.headers).to(haveCount(4))
                        expect(requestData?.headers[Header.sogsPubKey.rawValue]).to(equal("1588672ccb97f40bb57238989226cf429b575ba355443f47bc76c5ab144a96c65b"))
                        expect(requestData?.headers[Header.sogsTimestamp.rawValue]).to(equal("1234567890"))
                        expect(requestData?.headers[Header.sogsNonce.rawValue]).to(equal("pK6YRtQApl4NhECGizF0Cg=="))
                        expect(requestData?.headers[Header.sogsSignature.rawValue]).to(equal("TestSogsSignature".bytes.toBase64()))
                    }
                    
                    it("fails when the blindedKeyPair is not generated") {
                        mockSodium
                            .when { $0.blindedKeyPair(serverPublicKey: any(), edKeyPair: any(), genericHash: mockGenericHash) }
                            .thenReturn(nil)
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .rooms(
                                        db,
                                        server: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                    
                    it("fails when the sogsSignature is not generated") {
                        mockSodium
                            .when { $0.blindedKeyPair(serverPublicKey: any(), edKeyPair: any(), genericHash: mockGenericHash) }
                            .thenReturn(nil)
                        
                        mockStorage
                            .read { db in
                                OpenGroupAPI
                                    .rooms(
                                        db,
                                        server: "testserver",
                                        using: dependencies
                                    )
                            }
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPIError.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                }
            }
        }
    }
}

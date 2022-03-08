// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import PromiseKit
import Sodium
import SessionSnodeKit

import Quick
import Nimble

@testable import SessionMessagingKit

class OpenGroupAPISpec: QuickSpec {
    class TestResponseInfo: OnionRequestResponseInfoType {
        let requestData: TestApi.RequestData
        let code: Int
        let headers: [String: String]
        
        init(requestData: TestApi.RequestData, code: Int, headers: [String: String]) {
            self.requestData = requestData
            self.code = code
            self.headers = headers
        }
    }
    
    struct TestNonce16Generator: NonceGenerator16ByteType {
        var NonceBytes: Int = 16
        
        func nonce() -> Array<UInt8> { return Data(base64Encoded: "pK6YRtQApl4NhECGizF0Cg==")!.bytes }
    }
    
    struct TestNonce24Generator: NonceGenerator24ByteType {
        var NonceBytes: Int = 24
        
        func nonce() -> Array<UInt8> { return Data(base64Encoded: "pbTUizreT0sqJ2R2LloseQDyVL2RYztD")!.bytes }
    }

    class TestApi: OnionRequestAPIType {
        struct RequestData: Codable {
            let urlString: String?
            let httpMethod: String
            let headers: [String: String]
            let snodeMethod: String?
            let body: Data?
            
            let server: String
            let version: OnionRequestAPI.Version
            let publicKey: String?
        }
        
        class var mockResponse: Data? { return nil }
        
        static func sendOnionRequest(_ request: URLRequest, to server: String, using version: OnionRequestAPI.Version, with x25519PublicKey: String) -> Promise<(OnionRequestResponseInfoType, Data?)> {
            let responseInfo: TestResponseInfo = TestResponseInfo(
                requestData: RequestData(
                    urlString: request.url?.absoluteString,
                    httpMethod: (request.httpMethod ?? "GET"),
                    headers: (request.allHTTPHeaderFields ?? [:]),
                    snodeMethod: nil,
                    body: request.httpBody,
                    
                    server: server,
                    version: version,
                    publicKey: x25519PublicKey
                ),
                code: 200,
                headers: [:]
            )
            
            return Promise.value((responseInfo, mockResponse))
        }
        
        static func sendOnionRequest(to snode: Snode, invoking method: Snode.Method, with parameters: JSON, using version: OnionRequestAPI.Version, associatedWith publicKey: String?) -> Promise<Data> {
            // TODO: Test the 'responseInfo' somehow?
            return Promise.value(mockResponse!)
        }
    }

    // MARK: - Spec

    override func spec() {
        var testStorage: TestStorage!
        var testSodium: TestSodium!
        var testAeadXChaCha20Poly1305Ietf: TestAeadXChaCha20Poly1305Ietf!
        var testGenericHash: TestGenericHash!
        var testSign: TestSign!
        var testUserDefaults: TestUserDefaults!
        var dependencies: Dependencies!
        
        var response: (OnionRequestResponseInfoType, Codable)? = nil
        var pollResponse: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable?)]?
        var error: Error?

        describe("an OpenGroupAPI") {
            // MARK: - Configuration
            
            beforeEach {
                testStorage = TestStorage()
                testSodium = TestSodium()
                testAeadXChaCha20Poly1305Ietf = TestAeadXChaCha20Poly1305Ietf()
                testGenericHash = TestGenericHash()
                testSign = TestSign()
                testUserDefaults = TestUserDefaults()
                dependencies = Dependencies(
                    api: TestApi.self,
                    storage: testStorage,
                    sodium: testSodium,
                    aeadXChaCha20Poly1305Ietf: testAeadXChaCha20Poly1305Ietf,
                    sign: testSign,
                    genericHash: testGenericHash,
                    ed25519: TestEd25519.self,
                    nonceGenerator16: TestNonce16Generator(),
                    nonceGenerator24: TestNonce24Generator(),
                    standardUserDefaults: testUserDefaults,
                    date: Date(timeIntervalSince1970: 1234567890)
                )
                
                testStorage.mockData[.allOpenGroups] = [
                    "0": OpenGroup(
                        server: "testServer",
                        room: "testRoom",
                        publicKey: TestConstants.publicKey,
                        name: "Test",
                        groupDescription: nil,
                        imageID: nil,
                        infoUpdates: 0
                    )
                ]
                testStorage.mockData[.openGroupPublicKeys] = [
                    "testServer": TestConstants.publicKey
                ]
                testStorage.mockData[.userKeyPair] = try! ECKeyPair(
                    publicKeyData: Data.data(fromHex: TestConstants.publicKey)!,
                    privateKeyData: Data.data(fromHex: TestConstants.privateKey)!
                )
                testStorage.mockData[.userEdKeyPair] = Box.KeyPair(
                    publicKey: Data.data(fromHex: TestConstants.publicKey)!.bytes,
                    secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                )
                
                testGenericHash.mockData[.hashOutputLength] = []
                testSodium.mockData[.blindedKeyPair] = Box.KeyPair(
                    publicKey: Data.data(fromHex: TestConstants.publicKey)!.bytes,
                    secretKey: Data.data(fromHex: TestConstants.edSecretKey)!.bytes
                )
                testSodium.mockData[.sogsSignature] = "TestSogsSignature".bytes
                testSign.mockData[.signature] = "TestSignature".bytes
            }

            afterEach {
                testStorage = nil
                testSodium = nil
                testAeadXChaCha20Poly1305Ietf = nil
                testGenericHash = nil
                testSign = nil
                testUserDefaults = nil
                dependencies = nil
                
                response = nil
                pollResponse = nil
                error = nil
            }
            
            // MARK: - Batching & Polling
    
            context("when polling") {
                context("and given a correct response") {
                    beforeEach {
                        class LocalTestApi: TestApi {
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
                        
                        dependencies = dependencies.with(api: LocalTestApi.self)
                    }
                    
                    it("generates the correct request") {
                        OpenGroupAPI.poll("testServer", hasPerformedInitialPoll: false, timeSinceLastPoll: 0, using: dependencies)
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
                        expect(pollResponse?.values).to(haveCount(5))
                        expect(pollResponse?.keys).to(contain(.capabilities))
                        expect(pollResponse?.keys).to(contain(.roomPollInfo("testRoom", 0)))
                        expect(pollResponse?.keys).to(contain(.roomMessagesRecent("testRoom")))
                        expect(pollResponse?.keys).to(contain(.inbox))
                        expect(pollResponse?.keys).to(contain(.outbox))
                        expect(pollResponse?[.capabilities]?.0).to(beAKindOf(TestResponseInfo.self))
                        
                        // Validate request data
                        let requestData: TestApi.RequestData? = (pollResponse?[.capabilities]?.0 as? TestResponseInfo)?.requestData
                        expect(requestData?.urlString).to(equal("testServer/batch"))
                        expect(requestData?.httpMethod).to(equal("POST"))
                        expect(requestData?.server).to(equal("testServer"))
                        expect(requestData?.publicKey).to(equal("7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d"))
                    }
                    
                    it("retrieves recent messages if there was no last message") {
                        OpenGroupAPI
                            .poll(
                                "testServer",
                                hasPerformedInitialPoll: false,
                                timeSinceLastPoll: 0,
                                using: dependencies
                            )
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
                        testStorage.mockData[.openGroupSequenceNumber] = ["testServer.testRoom": Int64(123)]
                        
                        OpenGroupAPI
                            .poll(
                                "testServer",
                                hasPerformedInitialPoll: false,
                                timeSinceLastPoll: (OpenGroupAPI.Poller.maxInactivityPeriod + 1),
                                using: dependencies
                            )
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
                        testStorage.mockData[.openGroupSequenceNumber] = ["testServer.testRoom": Int64(123)]
                        
                        OpenGroupAPI
                            .poll(
                                "testServer",
                                hasPerformedInitialPoll: false,
                                timeSinceLastPoll: 0,
                                using: dependencies
                            )
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
                        testStorage.mockData[.openGroupSequenceNumber] = ["testServer.testRoom": Int64(123)]

                        OpenGroupAPI
                            .poll(
                                "testServer",
                                hasPerformedInitialPoll: true,
                                timeSinceLastPoll: 0,
                                using: dependencies
                            )
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
                    
                    it("retrieves recent inbox messages if there was no last message") {
                        OpenGroupAPI
                            .poll(
                                "testServer",
                                hasPerformedInitialPoll: true,
                                timeSinceLastPoll: 0,
                                using: dependencies
                            )
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
                        testStorage.mockData[.openGroupInboxLatestMessageId] = ["testServer": Int64(124)]
                        
                        OpenGroupAPI
                            .poll(
                                "testServer",
                                hasPerformedInitialPoll: true,
                                timeSinceLastPoll: 0,
                                using: dependencies
                            )
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
                        OpenGroupAPI
                            .poll(
                                "testServer",
                                hasPerformedInitialPoll: true,
                                timeSinceLastPoll: 0,
                                using: dependencies
                            )
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
                        testStorage.mockData[.openGroupOutboxLatestMessageId] = ["testServer": Int64(125)]
                        
                        OpenGroupAPI
                            .poll(
                                "testServer",
                                hasPerformedInitialPoll: true,
                                timeSinceLastPoll: 0,
                                using: dependencies
                            )
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
                
                context("and given an invalid response") {
                    it("does not update the poll state") {
                        testStorage.mockData[.openGroupSequenceNumber] = ["testServer.testRoom": Int64(123)]
                        
                        OpenGroupAPI.poll("testServer", hasPerformedInitialPoll: false, timeSinceLastPoll: 0, using: dependencies)
                            .get { result in pollResponse = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(HTTP.Error.invalidResponse.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(pollResponse).to(beNil())
                        expect(testUserDefaults[.lastOpen]).to(beNil())
                    }
                    
                    it("errors when no data is returned") {
                        OpenGroupAPI.poll("testServer", hasPerformedInitialPoll: false, timeSinceLastPoll: 0, using: dependencies)
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
                        class LocalTestApi: TestApi {
                            override class var mockResponse: Data? { return Data() }
                        }
                        dependencies = dependencies.with(api: LocalTestApi.self)
                        
                        OpenGroupAPI.poll("testServer", hasPerformedInitialPoll: false, timeSinceLastPoll: 0, using: dependencies)
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
                        class LocalTestApi: TestApi {
                            override class var mockResponse: Data? { return "[]".data(using: .utf8) }
                        }
                        dependencies = dependencies.with(api: LocalTestApi.self)
                        
                        OpenGroupAPI.poll("testServer", hasPerformedInitialPoll: false, timeSinceLastPoll: 0, using: dependencies)
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
                        class LocalTestApi: TestApi {
                            override class var mockResponse: Data? { return "{}".data(using: .utf8) }
                        }
                        dependencies = dependencies.with(api: LocalTestApi.self)
                        
                        OpenGroupAPI.poll("testServer", hasPerformedInitialPoll: false, timeSinceLastPoll: 0, using: dependencies)
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
                        class LocalTestApi: TestApi {
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
                        dependencies = dependencies.with(api: LocalTestApi.self)
                        
                        OpenGroupAPI.poll("testServer", hasPerformedInitialPoll: false, timeSinceLastPoll: 0, using: dependencies)
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
                    
                    it("errors when an unexpected response is returned") {
                        class LocalTestApi: TestApi {
                            override class var mockResponse: Data? {
                                let responses: [Data] = [
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
                        dependencies = dependencies.with(api: LocalTestApi.self)
                        
                        OpenGroupAPI.poll("testServer", hasPerformedInitialPoll: false, timeSinceLastPoll: 0, using: dependencies)
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
                    class LocalTestApi: TestApi {
                        static let data: OpenGroupAPI.Capabilities = OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: nil)
                        
                        override class var mockResponse: Data? { try! JSONEncoder().encode(data) }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                    
                    var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Capabilities)?
                    
                    OpenGroupAPI.capabilities(on: "testServer", using: dependencies)
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
                    expect(response?.data).to(equal(LocalTestApi.data))
                    
                    // Validate request data
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("GET"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/capabilities"))
                }
            }
            
            // MARK: - Rooms
            
            context("when doing a rooms request") {
                it("generates the request and handles the response correctly") {
                    class LocalTestApi: TestApi {
                        static let data: [OpenGroupAPI.Room] = [
                            OpenGroupAPI.Room(
                                token: "test",
                                name: "test",
                                description: nil,
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
                    dependencies = dependencies.with(api: LocalTestApi.self)
                    
                    var response: (info: OnionRequestResponseInfoType, data: [OpenGroupAPI.Room])?
                    
                    OpenGroupAPI.rooms(for: "testServer", using: dependencies)
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
                    expect(response?.data).to(equal(LocalTestApi.data))
                    
                    // Validate request data
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("GET"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/rooms"))
                }
            }
            
            // MARK: - CapabilitiesAndRoom
            
            context("when doing a capabilitiesAndRoom request") {
                context("and given a correct response") {
                    it("generates the request and handles the response correctly") {
                        class LocalTestApi: TestApi {
                            static let capabilitiesData: OpenGroupAPI.Capabilities = OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: nil)
                            static let roomData: OpenGroupAPI.Room = OpenGroupAPI.Room(
                                token: "test",
                                name: "test",
                                description: nil,
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
                        dependencies = dependencies.with(api: LocalTestApi.self)
                        
                        var response: (capabilities: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Capabilities?), room: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Room?))?
                        
                        OpenGroupAPI.capabilitiesAndRoom(for: "testRoom", on: "testServer", using: dependencies)
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
                        expect(response?.capabilities.data).to(equal(LocalTestApi.capabilitiesData))
                        expect(response?.room.data).to(equal(LocalTestApi.roomData))
                        
                        // Validate request data
                        let requestData: TestApi.RequestData? = (response?.capabilities.info as? TestResponseInfo)?.requestData
                        expect(requestData?.httpMethod).to(equal("POST"))
                        expect(requestData?.server).to(equal("testServer"))
                        expect(requestData?.urlString).to(equal("testServer/sequence"))
                    }
                }
                
                context("and given an invalid response") {
                    it("errors when only a capabilities response is returned") {
                        class LocalTestApi: TestApi {
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
                        dependencies = dependencies.with(api: LocalTestApi.self)
                        
                        var response: (capabilities: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Capabilities?), room: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Room?))?
                        
                        OpenGroupAPI.capabilitiesAndRoom(for: "testRoom", on: "testServer", using: dependencies)
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
                        class LocalTestApi: TestApi {
                            static let roomData: OpenGroupAPI.Room = OpenGroupAPI.Room(
                                token: "test",
                                name: "test",
                                description: nil,
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
                        dependencies = dependencies.with(api: LocalTestApi.self)
                        
                        var response: (capabilities: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Capabilities?), room: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Room?))?
                        
                        OpenGroupAPI.capabilitiesAndRoom(for: "testRoom", on: "testServer", using: dependencies)
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
                        class LocalTestApi: TestApi {
                            static let capabilitiesData: OpenGroupAPI.Capabilities = OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: nil)
                            static let roomData: OpenGroupAPI.Room = OpenGroupAPI.Room(
                                token: "test",
                                name: "test",
                                description: nil,
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
                        dependencies = dependencies.with(api: LocalTestApi.self)
                        
                        var response: (capabilities: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Capabilities?), room: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Room?))?
                        
                        OpenGroupAPI.capabilitiesAndRoom(for: "testRoom", on: "testServer", using: dependencies)
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
                    class LocalTestApi: TestApi {
                        static let data: OpenGroupAPI.Message = OpenGroupAPI.Message(
                            id: 126,
                            sender: "testSender",
                            posted: 321,
                            edited: nil,
                            seqNo: 10,
                            whisper: false,
                            whisperMods: false,
                            whisperTo: nil,
                            base64EncodedData: nil,
                            base64EncodedSignature: nil
                        )
                        
                        override class var mockResponse: Data? { return try! JSONEncoder().encode(data) }
                    }
                    messageData = LocalTestApi.data
                    dependencies = dependencies.with(api: LocalTestApi.self)
                    
                    testStorage.mockData[.userEdKeyPair] = Box.KeyPair(publicKey: [], secretKey: [])
                }
                
                afterEach {
                    messageData = nil
                }
                
                it("correctly sends the message") {
                    var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                    
                    OpenGroupAPI
                        .send(
                            "test".data(using: .utf8)!,
                            to: "testRoom",
                            on: "testServer",
                            whisperTo: nil,
                            whisperMods: false,
                            fileIds: nil,
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.0 as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/room/testRoom/message"))
                }
                
                it("saves the received message timestamp to the database in milliseconds") {
                    var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                    
                    OpenGroupAPI
                        .send(
                            "test".data(using: .utf8)!,
                            to: "testRoom",
                            on: "testServer",
                            whisperTo: nil,
                            whisperMods: false,
                            fileIds: nil,
                            using: dependencies
                        )
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    expect(testStorage.mockData[.receivedMessageTimestamp] as? UInt64).to(equal(321000))
                }
                
                context("when unblinded") {
                    beforeEach {
                        testStorage.mockData[.openGroupServer] = OpenGroupAPI.Server(
                            name: "testServer",
                            capabilities: OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: [])
                        )
                    }
                    
                    it("signs the message correctly") {
                        var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                        
                        OpenGroupAPI
                            .send(
                                "test".data(using: .utf8)!,
                                to: "testRoom",
                                on: "testServer",
                                whisperTo: nil,
                                whisperMods: false,
                                fileIds: nil,
                                using: dependencies
                            )
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
                        let requestData: TestApi.RequestData? = (response?.0 as? TestResponseInfo)?.requestData
                        let requestBody: OpenGroupAPI.SendMessageRequest = try! JSONDecoder().decode(OpenGroupAPI.SendMessageRequest.self, from: requestData!.body!)
                        
                        expect(requestBody.data).to(equal("test".data(using: .utf8)))
                        expect(requestBody.signature).to(equal("TestSignature".data(using: .utf8)))
                    }
                    
                    it("fails to sign if there is no public key") {
                        testStorage.mockData[.openGroupPublicKeys] = [:]
                        
                        var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                        
                        OpenGroupAPI
                            .send(
                                "test".data(using: .utf8)!,
                                to: "testRoom",
                                on: "testServer",
                                whisperTo: nil,
                                whisperMods: false,
                                fileIds: nil,
                                using: dependencies
                            )
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPI.Error.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                }
                
                context("when blinded") {
                    beforeEach {
                        testStorage.mockData[.openGroupServer] = OpenGroupAPI.Server(
                            name: "testServer",
                            capabilities: OpenGroupAPI.Capabilities(capabilities: [.sogs, .blind], missing: [])
                        )
                    }
                    
                    it("signs the message correctly") {
                        var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                        
                        OpenGroupAPI
                            .send(
                                "test".data(using: .utf8)!,
                                to: "testRoom",
                                on: "testServer",
                                whisperTo: nil,
                                whisperMods: false,
                                fileIds: nil,
                                using: dependencies
                            )
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
                        let requestData: TestApi.RequestData? = (response?.0 as? TestResponseInfo)?.requestData
                        let requestBody: OpenGroupAPI.SendMessageRequest = try! JSONDecoder().decode(OpenGroupAPI.SendMessageRequest.self, from: requestData!.body!)
                        
                        expect(requestBody.data).to(equal("test".data(using: .utf8)))
                        expect(requestBody.signature).to(equal("TestSogsSignature".data(using: .utf8)))
                    }
                    
                    it("fails to sign if there is no public key") {
                        testStorage.mockData[.openGroupPublicKeys] = [:]
                        
                        var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                        
                        OpenGroupAPI
                            .send(
                                "test".data(using: .utf8)!,
                                to: "testRoom",
                                on: "testServer",
                                whisperTo: nil,
                                whisperMods: false,
                                fileIds: nil,
                                using: dependencies
                            )
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPI.Error.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                }
            }
            
            context("when getting an individual message") {
                it("generates the request and handles the response correctly") {
                    class LocalTestApi: TestApi {
                        static let data: OpenGroupAPI.Message = OpenGroupAPI.Message(
                            id: 126,
                            sender: "testSender",
                            posted: 321,
                            edited: nil,
                            seqNo: 10,
                            whisper: false,
                            whisperMods: false,
                            whisperTo: nil,
                            base64EncodedData: nil,
                            base64EncodedSignature: nil
                        )
                        
                        override class var mockResponse: Data? { return try! JSONEncoder().encode(data) }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                    
                    var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.Message)?
                    
                    OpenGroupAPI.message(123, in: "testRoom", on: "testServer", using: dependencies)
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
                    expect(response?.data).to(equal(LocalTestApi.data))
                    
                    // Validate request data
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("GET"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/room/testRoom/message/123"))
                }
            }
            
            context("when updating a message") {
                beforeEach {
                    class LocalTestApi: TestApi {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                    
                    testStorage.mockData[.userEdKeyPair] = Box.KeyPair(publicKey: [], secretKey: [])
                }
                
                it("correctly sends the update") {
                    var response: (info: OnionRequestResponseInfoType, data: Data?)?
                    
                    OpenGroupAPI
                        .messageUpdate(
                            123,
                            plaintext: "test".data(using: .utf8)!,
                            fileIds: nil,
                            in: "testRoom",
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.0 as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("PUT"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/room/testRoom/message/123"))
                }
                
                context("when unblinded") {
                    beforeEach {
                        testStorage.mockData[.openGroupServer] = OpenGroupAPI.Server(
                            name: "testServer",
                            capabilities: OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: [])
                        )
                    }
                    
                    it("signs the message correctly") {
                        var response: (info: OnionRequestResponseInfoType, data: Data?)?
                        
                        OpenGroupAPI
                            .messageUpdate(
                                123,
                                plaintext: "test".data(using: .utf8)!,
                                fileIds: nil,
                                in: "testRoom",
                                on: "testServer",
                                using: dependencies
                            )
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
                        let requestData: TestApi.RequestData? = (response?.0 as? TestResponseInfo)?.requestData
                        let requestBody: OpenGroupAPI.UpdateMessageRequest = try! JSONDecoder().decode(OpenGroupAPI.UpdateMessageRequest.self, from: requestData!.body!)
                        
                        expect(requestBody.data).to(equal("test".data(using: .utf8)))
                        expect(requestBody.signature).to(equal("TestSignature".data(using: .utf8)))
                    }
                    
                    it("fails to sign if there is no public key") {
                        testStorage.mockData[.openGroupPublicKeys] = [:]
                        
                        var response: (info: OnionRequestResponseInfoType, data: Data?)?
                        
                        OpenGroupAPI
                            .messageUpdate(
                                123,
                                plaintext: "test".data(using: .utf8)!,
                                fileIds: nil,
                                in: "testRoom",
                                on: "testServer",
                                using: dependencies
                            )
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPI.Error.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                }
                
                context("when blinded") {
                    beforeEach {
                        testStorage.mockData[.openGroupServer] = OpenGroupAPI.Server(
                            name: "testServer",
                            capabilities: OpenGroupAPI.Capabilities(capabilities: [.sogs, .blind], missing: [])
                        )
                    }
                    
                    it("signs the message correctly") {
                        var response: (info: OnionRequestResponseInfoType, data: Data?)?
                        
                        OpenGroupAPI
                            .messageUpdate(
                                123,
                                plaintext: "test".data(using: .utf8)!,
                                fileIds: nil,
                                in: "testRoom",
                                on: "testServer",
                                using: dependencies
                            )
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
                        let requestData: TestApi.RequestData? = (response?.0 as? TestResponseInfo)?.requestData
                        let requestBody: OpenGroupAPI.UpdateMessageRequest = try! JSONDecoder().decode(OpenGroupAPI.UpdateMessageRequest.self, from: requestData!.body!)
                        
                        expect(requestBody.data).to(equal("test".data(using: .utf8)))
                        expect(requestBody.signature).to(equal("TestSogsSignature".data(using: .utf8)))
                    }
                    
                    it("fails to sign if there is no public key") {
                        testStorage.mockData[.openGroupPublicKeys] = [:]
                        
                        var response: (info: OnionRequestResponseInfoType, data: Data?)?
                        
                        OpenGroupAPI
                            .messageUpdate(
                                123,
                                plaintext: "test".data(using: .utf8)!,
                                fileIds: nil,
                                in: "testRoom",
                                on: "testServer",
                                using: dependencies
                            )
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPI.Error.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                }
            }
            
            context("when deleting a message") {
                it("generates the request and handles the response correctly") {
                    class LocalTestApi: TestApi {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                    
                    var response: (info: OnionRequestResponseInfoType, data: Data?)?
                    
                    OpenGroupAPI.messageDelete(123, in: "testRoom", on: "testServer", using: dependencies)
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
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("DELETE"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/room/testRoom/message/123"))
                }
            }
            
            // MARK: - Pinning
            
            context("when pinning a message") {
                it("generates the request and handles the response correctly") {
                    class LocalTestApi: TestApi {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                    
                    var response: OnionRequestResponseInfoType?
                    
                    OpenGroupAPI.pinMessage(id: 123, in: "testRoom", on: "testServer", using: dependencies)
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
                    let requestData: TestApi.RequestData? = (response as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/room/testRoom/pin/123"))
                }
            }
            
            context("when unpinning a message") {
                it("generates the request and handles the response correctly") {
                    class LocalTestApi: TestApi {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                    
                    var response: OnionRequestResponseInfoType?
                    
                    OpenGroupAPI.unpinMessage(id: 123, in: "testRoom", on: "testServer", using: dependencies)
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
                    let requestData: TestApi.RequestData? = (response as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/room/testRoom/unpin/123"))
                }
            }
            
            context("when unpinning all messages") {
                it("generates the request and handles the response correctly") {
                    class LocalTestApi: TestApi {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                    
                    var response: OnionRequestResponseInfoType?
                    
                    OpenGroupAPI.unpinAll(in: "testRoom", on: "testServer", using: dependencies)
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
                    let requestData: TestApi.RequestData? = (response as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/room/testRoom/unpin/all"))
                }
            }
            
            // MARK: - Files
            
            context("when uploading files") {
                it("generates the request and handles the response correctly") {
                    class LocalTestApi: TestApi {
                        override class var mockResponse: Data? {
                            return try! JSONEncoder().encode(FileUploadResponse(id: "1"))
                        }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                    
                    OpenGroupAPI.uploadFile([], to: "testRoom", on: "testServer", using: dependencies)
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
                    let requestData: TestApi.RequestData? = (response?.0 as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/room/testRoom/file"))
                }
                
                it("doesn't add a fileName to the content-disposition header when not provided") {
                    class LocalTestApi: TestApi {
                        override class var mockResponse: Data? {
                            return try! JSONEncoder().encode(FileUploadResponse(id: "1"))
                        }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                    
                    OpenGroupAPI.uploadFile([], to: "testRoom", on: "testServer", using: dependencies)
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
                    let requestData: TestApi.RequestData? = (response?.0 as? TestResponseInfo)?.requestData
                    expect(requestData?.headers[Header.contentDisposition.rawValue])
                        .toNot(contain("filename"))
                }
                
                it("adds the fileName to the content-disposition header when provided") {
                    class LocalTestApi: TestApi {
                        override class var mockResponse: Data? {
                            return try! JSONEncoder().encode(FileUploadResponse(id: "1"))
                        }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                    
                    OpenGroupAPI.uploadFile([], fileName: "TestFileName", to: "testRoom", on: "testServer", using: dependencies)
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
                    let requestData: TestApi.RequestData? = (response?.0 as? TestResponseInfo)?.requestData
                    expect(requestData?.headers[Header.contentDisposition.rawValue]).to(contain("TestFileName"))
                }
            }
            
            context("when downloading files") {
                it("generates the request and handles the response correctly") {
                    class LocalTestApi: TestApi {
                        override class var mockResponse: Data? {
                            return Data()
                        }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                    
                    OpenGroupAPI.downloadFile(1, from: "testRoom", on: "testServer", using: dependencies)
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
                    let requestData: TestApi.RequestData? = (response?.0 as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("GET"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/room/testRoom/file/1"))
                }
            }
            
            // MARK: - Inbox/Outbox (Message Requests)
            
            context("when sending message requests") {
                var messageData: OpenGroupAPI.SendDirectMessageResponse!
                
                beforeEach {
                    class LocalTestApi: TestApi {
                        static let data: OpenGroupAPI.SendDirectMessageResponse = OpenGroupAPI.SendDirectMessageResponse(
                            id: 126,
                            sender: "testSender",
                            recipient: "testRecipient",
                            posted: 321,
                            expires: 456
                        )
                        
                        override class var mockResponse: Data? { return try! JSONEncoder().encode(data) }
                    }
                    messageData = LocalTestApi.data
                    dependencies = dependencies.with(api: LocalTestApi.self)
                }
                
                afterEach {
                    messageData = nil
                }
                
                it("correctly sends the message request") {
                    var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.SendDirectMessageResponse)?
                    
                    OpenGroupAPI
                        .send(
                            "test".data(using: .utf8)!,
                            toInboxFor: "testUserId",
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.0 as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/inbox/testUserId"))
                }
                
                it("saves the received message timestamp to the database in milliseconds") {
                    var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.SendDirectMessageResponse)?
                    
                    OpenGroupAPI
                        .send(
                            "test".data(using: .utf8)!,
                            toInboxFor: "testUserId",
                            on: "testServer",
                            using: dependencies
                        )
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(response)
                        .toEventuallyNot(
                            beNil(),
                            timeout: .milliseconds(100)
                        )
                    expect(error?.localizedDescription).to(beNil())
                    expect(testStorage.mockData[.receivedMessageTimestamp] as? UInt64).to(equal(321000))
                }
            }
            
            // MARK: - Users
            
            context("when banning a user") {
                var response: (info: OnionRequestResponseInfoType, data: Data?)?
                
                beforeEach {
                    class LocalTestApi: TestApi {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                }
                
                afterEach {
                    response = nil
                }
                
                it("generates the request and handles the response correctly") {
                    OpenGroupAPI
                        .userBan(
                            "testUserId",
                            for: nil,
                            from: nil,
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/user/testUserId/ban"))
                }
                
                it("does a global ban if no room tokens are provided") {
                    OpenGroupAPI
                        .userBan(
                            "testUserId",
                            for: nil,
                            from: nil,
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserBanRequest = try! JSONDecoder().decode(OpenGroupAPI.UserBanRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beTrue())
                    expect(requestBody.rooms).to(beNil())
                }
                
                it("does room specific bans if room tokens are provided") {
                    OpenGroupAPI
                        .userBan(
                            "testUserId",
                            for: nil,
                            from: ["testRoom"],
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserBanRequest = try! JSONDecoder().decode(OpenGroupAPI.UserBanRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beNil())
                    expect(requestBody.rooms).to(equal(["testRoom"]))
                }
            }
            
            context("when unbanning a user") {
                var response: (info: OnionRequestResponseInfoType, data: Data?)?
                
                beforeEach {
                    class LocalTestApi: TestApi {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                }
                
                afterEach {
                    response = nil
                }
                
                it("generates the request and handles the response correctly") {
                    OpenGroupAPI
                        .userUnban(
                            "testUserId",
                            from: nil,
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/user/testUserId/unban"))
                }
                
                it("does a global ban if no room tokens are provided") {
                    OpenGroupAPI
                        .userUnban(
                            "testUserId",
                            from: nil,
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserUnbanRequest = try! JSONDecoder().decode(OpenGroupAPI.UserUnbanRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beTrue())
                    expect(requestBody.rooms).to(beNil())
                }
                
                it("does room specific bans if room tokens are provided") {
                    OpenGroupAPI
                        .userUnban(
                            "testUserId",
                            from: ["testRoom"],
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserUnbanRequest = try! JSONDecoder().decode(OpenGroupAPI.UserUnbanRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beNil())
                    expect(requestBody.rooms).to(equal(["testRoom"]))
                }
            }
            
            context("when updating a users permissions") {
                var response: (info: OnionRequestResponseInfoType, data: Data?)?
                
                beforeEach {
                    class LocalTestApi: TestApi {
                        override class var mockResponse: Data? { return Data() }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                }
                
                afterEach {
                    response = nil
                }
                
                it("generates the request and handles the response correctly") {
                    OpenGroupAPI
                        .userModeratorUpdate(
                            "testUserId",
                            moderator: true,
                            admin: nil,
                            visible: true,
                            for: nil,
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/user/testUserId/moderator"))
                }
                
                it("does a global update if no room tokens are provided") {
                    OpenGroupAPI
                        .userModeratorUpdate(
                            "testUserId",
                            moderator: true,
                            admin: nil,
                            visible: true,
                            for: nil,
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserModeratorRequest = try! JSONDecoder().decode(OpenGroupAPI.UserModeratorRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beTrue())
                    expect(requestBody.rooms).to(beNil())
                }
                
                it("does room specific updates if room tokens are provided") {
                    OpenGroupAPI
                        .userModeratorUpdate(
                            "testUserId",
                            moderator: true,
                            admin: nil,
                            visible: true,
                            for: ["testRoom"],
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserModeratorRequest = try! JSONDecoder().decode(OpenGroupAPI.UserModeratorRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beNil())
                    expect(requestBody.rooms).to(equal(["testRoom"]))
                }
                
                it("fails if neither moderator or admin are set") {
                    OpenGroupAPI
                        .userModeratorUpdate(
                            "testUserId",
                            moderator: nil,
                            admin: nil,
                            visible: true,
                            for: nil,
                            on: "testServer",
                            using: dependencies
                        )
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
            
            context("when deleting a users messages") {
                var response: (info: OnionRequestResponseInfoType, data: OpenGroupAPI.UserDeleteMessagesResponse)?
                var messageData: OpenGroupAPI.UserDeleteMessagesResponse!
                
                beforeEach {
                    class LocalTestApi: TestApi {
                        static let data: OpenGroupAPI.UserDeleteMessagesResponse = OpenGroupAPI.UserDeleteMessagesResponse(
                            id: "testId",
                            messagesDeleted: 10
                        )
                        
                        override class var mockResponse: Data? { return try! JSONEncoder().encode(data) }
                    }
                    messageData = LocalTestApi.data
                    dependencies = dependencies.with(api: LocalTestApi.self)
                }
                
                afterEach {
                    response = nil
                }
                
                it("generates the request and handles the response correctly") {
                    OpenGroupAPI
                        .userDeleteMessages(
                            "testUserId",
                            from: nil,
                            on: "testServer",
                            using: dependencies
                        )
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
                    
                    // Validate request data
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/user/testUserId/deleteMessages"))
                }
                
                it("does a global delete if no room tokens are provided") {
                    OpenGroupAPI
                        .userDeleteMessages(
                            "testUserId",
                            from: nil,
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserDeleteMessagesRequest = try! JSONDecoder().decode(OpenGroupAPI.UserDeleteMessagesRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beTrue())
                    expect(requestBody.rooms).to(beNil())
                }
                
                it("does room specific bans if room tokens are provided") {
                    OpenGroupAPI
                        .userDeleteMessages(
                            "testUserId",
                            from: ["testRoom"],
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.info as? TestResponseInfo)?.requestData
                    let requestBody: OpenGroupAPI.UserDeleteMessagesRequest = try! JSONDecoder().decode(OpenGroupAPI.UserDeleteMessagesRequest.self, from: requestData!.body!)
                    
                    expect(requestBody.global).to(beNil())
                    expect(requestBody.rooms).to(equal(["testRoom"]))
                }
            }
            
            context("when banning and deleting all messages for a user") {
                var response: [OnionRequestResponseInfoType]?
                
                beforeEach {
                    class LocalTestApi: TestApi {
                        static let deleteMessagesData: OpenGroupAPI.UserDeleteMessagesResponse = OpenGroupAPI.UserDeleteMessagesResponse(
                            id: "123",
                            messagesDeleted: 10
                        )
                        
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
                                    OpenGroupAPI.BatchSubResponse(
                                        code: 200,
                                        headers: [:],
                                        body: deleteMessagesData,
                                        failedToParseBody: false
                                    )
                                )
                            ]
                            
                            return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
                        }
                    }
                    dependencies = dependencies.with(api: LocalTestApi.self)
                }
                
                afterEach {
                    response = nil
                }
                
                it("generates the request and handles the response correctly") {
                    OpenGroupAPI
                        .userBanAndDeleteAllMessage(
                            "testUserId",
                            from: nil,
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.first as? TestResponseInfo)?.requestData
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.server).to(equal("testServer"))
                    expect(requestData?.urlString).to(equal("testServer/sequence"))
                }
                
                it("does a global ban and delete if no room tokens are provided") {
                    OpenGroupAPI
                        .userBanAndDeleteAllMessage(
                            "testUserId",
                            from: nil,
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.first as? TestResponseInfo)?.requestData
                    let jsonObject: Any = try! JSONSerialization.jsonObject(
                        with: requestData!.body!,
                        options: [.fragmentsAllowed]
                    )
                    let anyArray: [Any] = jsonObject as! [Any]
                    let dataArray: [Data] = anyArray.compactMap {
                        try! JSONSerialization.data(withJSONObject: ($0 as! [String: Any])["json"]!)
                    }
                    let firstRequestBody: OpenGroupAPI.UserBanRequest = try! JSONDecoder()
                        .decode(OpenGroupAPI.UserBanRequest.self, from: dataArray.first!)
                    let lastRequestBody: OpenGroupAPI.UserDeleteMessagesRequest = try! JSONDecoder()
                        .decode(OpenGroupAPI.UserDeleteMessagesRequest.self, from: dataArray.last!)
                    
                    expect(firstRequestBody.global).to(beTrue())
                    expect(firstRequestBody.rooms).to(beNil())
                    expect(lastRequestBody.global).to(beTrue())
                    expect(lastRequestBody.rooms).to(beNil())
                }
                
                it("does room specific bans and deletes if room tokens are provided") {
                    OpenGroupAPI
                        .userBanAndDeleteAllMessage(
                            "testUserId",
                            from: ["testRoom"],
                            on: "testServer",
                            using: dependencies
                        )
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
                    let requestData: TestApi.RequestData? = (response?.first as? TestResponseInfo)?.requestData
                    let jsonObject: Any = try! JSONSerialization.jsonObject(
                        with: requestData!.body!,
                        options: [.fragmentsAllowed]
                    )
                    let anyArray: [Any] = jsonObject as! [Any]
                    let dataArray: [Data] = anyArray.compactMap {
                        try! JSONSerialization.data(withJSONObject: ($0 as! [String: Any])["json"]!)
                    }
                    let firstRequestBody: OpenGroupAPI.UserBanRequest = try! JSONDecoder()
                        .decode(OpenGroupAPI.UserBanRequest.self, from: dataArray.first!)
                    let lastRequestBody: OpenGroupAPI.UserDeleteMessagesRequest = try! JSONDecoder()
                        .decode(OpenGroupAPI.UserDeleteMessagesRequest.self, from: dataArray.last!)
                    
                    expect(firstRequestBody.global).to(beNil())
                    expect(firstRequestBody.rooms).to(equal(["testRoom"]))
                    expect(lastRequestBody.global).to(beNil())
                    expect(lastRequestBody.rooms).to(equal(["testRoom"]))
                }
            }
            
            // MARK: - Authentication
            
            context("when signing") {
                beforeEach {
                    class LocalTestApi: TestApi {
                        override class var mockResponse: Data? {
                            return try! JSONEncoder().encode([OpenGroupAPI.Room]())
                        }
                    }
                    
                    dependencies = dependencies.with(api: LocalTestApi.self)
                }
                
                it("fails when there is no userEdKeyPair") {
                    testStorage.mockData[.userEdKeyPair] = nil
                    
                    OpenGroupAPI.rooms(for: "testServer", using: dependencies)
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(error?.localizedDescription)
                        .toEventually(
                            equal(OpenGroupAPI.Error.signingFailed.localizedDescription),
                            timeout: .milliseconds(100)
                        )
                    
                    expect(response).to(beNil())
                }
                
                it("fails when there is no serverPublicKey") {
                    testStorage.mockData[.openGroupPublicKeys] = [:]
                    
                    OpenGroupAPI.rooms(for: "testServer", using: dependencies)
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(error?.localizedDescription)
                        .toEventually(
                            equal(OpenGroupAPI.Error.noPublicKey.localizedDescription),
                            timeout: .milliseconds(100)
                        )
                    
                    expect(response).to(beNil())
                }
                
                it("fails when the serverPublicKey is not a hex string") {
                    testStorage.mockData[.openGroupPublicKeys] = ["testServer": "TestString!!!"]
                    
                    OpenGroupAPI.rooms(for: "testServer", using: dependencies)
                        .get { result in response = result }
                        .catch { requestError in error = requestError }
                        .retainUntilComplete()
                    
                    expect(error?.localizedDescription)
                        .toEventually(
                            equal(OpenGroupAPI.Error.signingFailed.localizedDescription),
                            timeout: .milliseconds(100)
                        )
                    
                    expect(response).to(beNil())
                }
                
                context("when unblinded") {
                    beforeEach {
                        testStorage.mockData[.openGroupServer] = OpenGroupAPI.Server(
                            name: "testServer",
                            capabilities: OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: [])
                        )
                    }
                    
                    it("signs correctly") {
                        OpenGroupAPI.rooms(for: "testServer", using: dependencies)
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
                        let requestData: TestApi.RequestData? = (response?.0 as? TestResponseInfo)?.requestData
                        expect(requestData?.urlString).to(equal("testServer/rooms"))
                        expect(requestData?.httpMethod).to(equal("GET"))
                        expect(requestData?.server).to(equal("testServer"))
                        expect(requestData?.publicKey).to(equal("7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d"))
                        expect(requestData?.headers).to(haveCount(4))
                        expect(requestData?.headers[Header.sogsPubKey.rawValue])
                            .to(equal("007aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d"))
                        expect(requestData?.headers[Header.sogsTimestamp.rawValue]).to(equal("1234567890"))
                        expect(requestData?.headers[Header.sogsNonce.rawValue]).to(equal("pK6YRtQApl4NhECGizF0Cg=="))
                        expect(requestData?.headers[Header.sogsSignature.rawValue]).to(equal("TestSignature".bytes.toBase64()))
                    }
                    
                    it("fails when the signature is not generated") {
                        testSign.mockData[.signature] = nil
                        
                        OpenGroupAPI.rooms(for: "testServer", using: dependencies)
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPI.Error.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                }
                
                context("when blinded") {
                    beforeEach {
                        testStorage.mockData[.openGroupServer] = OpenGroupAPI.Server(
                            name: "testServer",
                            capabilities: OpenGroupAPI.Capabilities(capabilities: [.sogs, .blind], missing: [])
                        )
                    }
                    
                    it("signs correctly") {
                        OpenGroupAPI.rooms(for: "testServer", using: dependencies)
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
                        let requestData: TestApi.RequestData? = (response?.0 as? TestResponseInfo)?.requestData
                        expect(requestData?.urlString).to(equal("testServer/rooms"))
                        expect(requestData?.httpMethod).to(equal("GET"))
                        expect(requestData?.server).to(equal("testServer"))
                        expect(requestData?.publicKey).to(equal("7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d"))
                        expect(requestData?.headers).to(haveCount(4))
                        expect(requestData?.headers[Header.sogsPubKey.rawValue]).to(equal("157aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d"))
                        expect(requestData?.headers[Header.sogsTimestamp.rawValue]).to(equal("1234567890"))
                        expect(requestData?.headers[Header.sogsNonce.rawValue]).to(equal("pK6YRtQApl4NhECGizF0Cg=="))
                        expect(requestData?.headers[Header.sogsSignature.rawValue]).to(equal("TestSogsSignature".bytes.toBase64()))
                    }
                    
                    it("fails when the blindedKeyPair is not generated") {
                        testSodium.mockData[.blindedKeyPair] = nil
                        
                        OpenGroupAPI.rooms(for: "testServer", using: dependencies)
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPI.Error.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                    
                    it("fails when the sogsSignature is not generated") {
                        testSodium.mockData[.sogsSignature] = nil
                        
                        OpenGroupAPI.rooms(for: "testServer", using: dependencies)
                            .get { result in response = result }
                            .catch { requestError in error = requestError }
                            .retainUntilComplete()
                        
                        expect(error?.localizedDescription)
                            .toEventually(
                                equal(OpenGroupAPI.Error.signingFailed.localizedDescription),
                                timeout: .milliseconds(100)
                            )
                        
                        expect(response).to(beNil())
                    }
                }
            }
        }
    }
}

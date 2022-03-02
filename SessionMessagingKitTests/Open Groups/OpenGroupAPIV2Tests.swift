// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import XCTest
import Nimble
import PromiseKit
import Sodium
import SessionSnodeKit

@testable import SessionMessagingKit

class OpenGroupAPITests: XCTestCase {
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
    
    var testStorage: TestStorage!
    var testSodium: TestSodium!
    var testAeadXChaCha20Poly1305Ietf: TestAeadXChaCha20Poly1305Ietf!
    var testGenericHash: TestGenericHash!
    var testSign: TestSign!
    var dependencies: OpenGroupAPI.Dependencies!

    // MARK: - Configuration
    
    override func setUpWithError() throws {
        testStorage = TestStorage()
        testSodium = TestSodium()
        testAeadXChaCha20Poly1305Ietf = TestAeadXChaCha20Poly1305Ietf()
        testGenericHash = TestGenericHash()
        testSign = TestSign()
        dependencies = OpenGroupAPI.Dependencies(
            api: TestApi.self,
            storage: testStorage,
            sodium: testSodium,
            aeadXChaCha20Poly1305Ietf: testAeadXChaCha20Poly1305Ietf,
            sign: testSign,
            genericHash: testGenericHash,
            ed25519: TestEd25519.self,
            nonceGenerator16: TestNonce16Generator(),
            nonceGenerator24: TestNonce24Generator(),
            date: Date(timeIntervalSince1970: 1234567890)
        )
        
        testStorage.mockData[.allOpenGroups] = [
            "0": OpenGroup(
                server: "testServer",
                room: "testRoom",
                publicKey: "7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d",
                name: "Test",
                groupDescription: nil,
                imageID: nil,
                infoUpdates: 0
            )
        ]
        testStorage.mockData[.openGroupPublicKeys] = [
            "testServer": "7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d"
        ]
        
        // Test Private key, not actually used (from here https://www.notion.so/oxen/SOGS-Authentication-dc64cc846cb24b2abbf7dd4bfd74abbb)
        testStorage.mockData[.userKeyPair] = try! ECKeyPair(
            publicKeyData: Data.data(fromHex: "7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d")!,
            privateKeyData: Data.data(fromHex: "881132ee03dbd2da065aa4c94f96081f62142dc8011d1b7a00de83e4aab38ce4")!
        )
        testStorage.mockData[.userEdKeyPair] = Box.KeyPair(
            publicKey: Data.data(fromHex: "7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d")!.bytes,
            secretKey: Data.data(fromHex: "881132ee03dbd2da065aa4c94f96081f62142dc8011d1b7a00de83e4aab38ce4881132ee03dbd2da065aa4c94f96081f62142dc8011d1b7a00de83e4aab38ce4")!.bytes
        )
        
        testGenericHash.mockData[.hashOutputLength] = []
        testSodium.mockData[.blindedKeyPair] = Box.KeyPair(
            publicKey: Data.data(fromHex: "7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d")!.bytes,
            secretKey: Data.data(fromHex: "881132ee03dbd2da065aa4c94f96081f62142dc8011d1b7a00de83e4aab38ce4881132ee03dbd2da065aa4c94f96081f62142dc8011d1b7a00de83e4aab38ce4")!.bytes
        )
        testSodium.mockData[.sogsSignature] = "TestSogsSignature".bytes
        testSign.mockData[.signature] = "TestSignature".bytes
    }

    override func tearDownWithError() throws {
        dependencies = nil
        testStorage = nil
    }
    
    // MARK: - Batching & Polling
    
    func testPollGeneratesTheCorrectRequest() throws {
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
                    )
                ]
                
                return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
            }
        }
        dependencies = dependencies.with(api: LocalTestApi.self)
        
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable?)]? = nil
        var error: Error? = nil
        
        OpenGroupAPI.poll("testServer", using: dependencies)
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
        expect(response?.values).to(haveCount(3))
        expect(response?.keys).to(contain(.capabilities))
        expect(response?.keys).to(contain(.roomPollInfo("testRoom", 0)))
        expect(response?.keys).to(contain(.roomMessagesRecent("testRoom")))
        expect(response?[.capabilities]?.0).to(beAKindOf(TestResponseInfo.self))
        
        // Validate request data
        let requestData: TestApi.RequestData? = (response?[.capabilities]?.0 as? TestResponseInfo)?.requestData
        expect(requestData?.urlString).to(equal("testServer/batch"))
        expect(requestData?.httpMethod).to(equal("POST"))
        expect(requestData?.server).to(equal("testServer"))
        expect(requestData?.publicKey).to(equal("7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d"))
    }
    
    func testPollReturnsAnErrorWhenGivenNoData() throws {
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable?)]? = nil
        var error: Error? = nil
        
        OpenGroupAPI.poll("testServer", using: dependencies)
            .get { result in response = result }
            .catch { requestError in error = requestError }
            .retainUntilComplete()
        
        expect(error?.localizedDescription)
            .toEventually(
                equal(OpenGroupAPI.Error.parsingFailed.localizedDescription),
                timeout: .milliseconds(100)
            )
        
        expect(response).to(beNil())
    }
    
    func testPollReturnsAnErrorWhenGivenInvalidData() throws {
        class LocalTestApi: TestApi {
            override class var mockResponse: Data? { return Data() }
        }
        dependencies = dependencies.with(api: LocalTestApi.self)
        
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable?)]? = nil
        var error: Error? = nil
        
        OpenGroupAPI.poll("testServer", using: dependencies)
            .get { result in response = result }
            .catch { requestError in error = requestError }
            .retainUntilComplete()
        
        expect(error?.localizedDescription)
            .toEventually(
                equal(OpenGroupAPI.Error.parsingFailed.localizedDescription),
                timeout: .milliseconds(100)
            )
        
        expect(response).to(beNil())
    }
    
    func testPollReturnsAnErrorWhenGivenAnEmptyResponse() throws {
        class LocalTestApi: TestApi {
            override class var mockResponse: Data? { return "[]".data(using: .utf8) }
        }
        dependencies = dependencies.with(api: LocalTestApi.self)
        
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable?)]? = nil
        var error: Error? = nil
        
        OpenGroupAPI.poll("testServer", using: dependencies)
            .get { result in response = result }
            .catch { requestError in error = requestError }
            .retainUntilComplete()
        
        expect(error?.localizedDescription)
            .toEventually(
                equal(OpenGroupAPI.Error.parsingFailed.localizedDescription),
                timeout: .milliseconds(100)
            )
        
        expect(response).to(beNil())
    }
    
    func testPollReturnsAnErrorWhenGivenAnObjectResponse() throws {
        class LocalTestApi: TestApi {
            override class var mockResponse: Data? { return "{}".data(using: .utf8) }
        }
        dependencies = dependencies.with(api: LocalTestApi.self)
        
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable?)]? = nil
        var error: Error? = nil
        
        OpenGroupAPI.poll("testServer", using: dependencies)
            .get { result in response = result }
            .catch { requestError in error = requestError }
            .retainUntilComplete()
        
        expect(error?.localizedDescription)
            .toEventually(
                equal(OpenGroupAPI.Error.parsingFailed.localizedDescription),
                timeout: .milliseconds(100)
            )
        
        expect(response).to(beNil())
    }
    
    func testPollReturnsAnErrorWhenGivenAnDifferentNumberOfResponses() throws {
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
        
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable?)]? = nil
        var error: Error? = nil
        
        OpenGroupAPI.poll("testServer", using: dependencies)
            .get { result in response = result }
            .catch { requestError in error = requestError }
            .retainUntilComplete()
        
        expect(error?.localizedDescription)
            .toEventually(
                equal(OpenGroupAPI.Error.parsingFailed.localizedDescription),
                timeout: .milliseconds(100)
            )
        
        expect(response).to(beNil())
    }
    
    func testPollReturnsAnErrorWhenGivenAnUnexpectedResponse() throws {
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
        
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable?)]? = nil
        var error: Error? = nil
        
        OpenGroupAPI.poll("testServer", using: dependencies)
            .get { result in response = result }
            .catch { requestError in error = requestError }
            .retainUntilComplete()
        
        expect(error?.localizedDescription)
            .toEventually(
                equal(OpenGroupAPI.Error.parsingFailed.localizedDescription),
                timeout: .milliseconds(100)
            )
        
        expect(response).to(beNil())
    }
    
    // MARK: - Files
    
    func testItDoesNotAddAFileNameHeaderWhenNotProvided() throws {
        class LocalTestApi: TestApi {
            override class var mockResponse: Data? {
                return try! JSONEncoder().encode(FileUploadResponse(id: 1))
            }
        }
        dependencies = dependencies.with(api: LocalTestApi.self)
        
        var response: (OnionRequestResponseInfoType, FileUploadResponse)? = nil
        var error: Error? = nil
        
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
        expect(requestData?.urlString).to(equal("testServer/room/testRoom/file"))
        expect(requestData?.httpMethod).to(equal("POST"))
        expect(requestData?.headers).to(haveCount(4))
        expect(requestData?.headers.keys).toNot(contain(Header.fileName.rawValue))
    }
    
    func testItAddsAFileNameHeaderWhenProvided() throws {
        class LocalTestApi: TestApi {
            override class var mockResponse: Data? {
                return try! JSONEncoder().encode(FileUploadResponse(id: 1))
            }
        }
        dependencies = dependencies.with(api: LocalTestApi.self)
        
        var response: (OnionRequestResponseInfoType, FileUploadResponse)? = nil
        var error: Error? = nil
        
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
        expect(requestData?.urlString).to(equal("testServer/room/testRoom/file"))
        expect(requestData?.httpMethod).to(equal("POST"))
        expect(requestData?.headers).to(haveCount(5))
        expect(requestData?.headers[Header.fileName.rawValue]).to(equal("TestFileName"))
    }
    
    // MARK: - Authentication
    
    func testItSignsTheUnblindedRequestCorrectly() throws {
        class LocalTestApi: TestApi {
            override class var mockResponse: Data? {
                return try! JSONEncoder().encode([OpenGroupAPI.Room]())
            }
        }
        testStorage.mockData[.openGroupServer] = OpenGroupAPI.Server(
            name: "testServer",
            capabilities: OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: [])
        )
        dependencies = dependencies.with(api: LocalTestApi.self)
        
        var response: (OnionRequestResponseInfoType, [OpenGroupAPI.Room])? = nil
        var error: Error? = nil
        
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
        expect(requestData?.headers[Header.sogsPubKey.rawValue]).to(equal("007aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d"))
        expect(requestData?.headers[Header.sogsTimestamp.rawValue]).to(equal("1234567890"))
        expect(requestData?.headers[Header.sogsNonce.rawValue]).to(equal("pK6YRtQApl4NhECGizF0Cg=="))
        expect(requestData?.headers[Header.sogsSignature.rawValue]).to(equal("TestSignature".bytes.toBase64()))
    }
    
    func testItSignsTheBlindedRequestCorrectly() throws {
        class LocalTestApi: TestApi {
            override class var mockResponse: Data? {
                return try! JSONEncoder().encode([OpenGroupAPI.Room]())
            }
        }
        testStorage.mockData[.openGroupServer] = OpenGroupAPI.Server(
            name: "testServer",
            capabilities: OpenGroupAPI.Capabilities(capabilities: [.sogs, .blind], missing: [])
        )
        dependencies = dependencies.with(api: LocalTestApi.self)
        
        var response: (OnionRequestResponseInfoType, [OpenGroupAPI.Room])? = nil
        var error: Error? = nil
        
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
    
    func testItFailsToSignIfThereIsNoUserEdKeyPair() throws {
        testStorage.mockData[.userEdKeyPair] = nil
        
        var response: Any? = nil
        var error: Error? = nil
        
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
    
    func testItFailsToSignIfTheServerPublicKeyIsInvalid() throws {
        testStorage.mockData[.openGroupPublicKeys] = [:]
        
        var response: Any? = nil
        var error: Error? = nil
        
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
    
    func testItFailsToSignIfBlindedAndTheBlindedKeyDoesNotGetGenerated() throws {
        class InvalidSodium: SodiumType {
            func getGenericHash() -> GenericHashType { return Sodium().genericHash }
            func getAeadXChaCha20Poly1305Ietf() -> AeadXChaCha20Poly1305IetfType { return Sodium().aead.xchacha20poly1305ietf }
            func getSign() -> SignType { return Sodium().sign }
            
            func generateBlindingFactor(serverPublicKey: String) -> Bytes? { return nil }
            func blindedKeyPair(serverPublicKey: String, edKeyPair: Box.KeyPair, genericHash: GenericHashType) -> Box.KeyPair? {
                return nil
            }
            func sogsSignature(message: Bytes, secretKey: Bytes, blindedSecretKey ka: Bytes, blindedPublicKey kA: Bytes) -> Bytes? {
                return nil
            }
            
            func combineKeys(lhsKeyBytes: Bytes, rhsKeyBytes: Bytes) -> Bytes? { return nil }
            func sharedBlindedEncryptionKey(secretKey a: Bytes, otherBlindedPublicKey: Bytes, fromBlindedPublicKey kA: Bytes, toBlindedPublicKey kB: Bytes, genericHash: GenericHashType) -> Bytes? {
                return nil
            }
            
            func sessionId(_ sessionId: String, matchesBlindedId blindedSessionId: String, serverPublicKey: String) -> Bool {
                return false
            }
        }
        testStorage.mockData[.openGroupServer] = OpenGroupAPI.Server(
            name: "testServer",
            capabilities: OpenGroupAPI.Capabilities(capabilities: [.sogs, .blind], missing: [])
        )
        dependencies = dependencies.with(sodium: InvalidSodium())
        
        var response: Any? = nil
        var error: Error? = nil
        
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
    
    func testItFailsToSignIfBlindedAndTheSogsSignatureDoesNotGetGenerated() throws {
        class InvalidSodium: SodiumType {
            func getGenericHash() -> GenericHashType { return Sodium().genericHash }
            func getAeadXChaCha20Poly1305Ietf() -> AeadXChaCha20Poly1305IetfType { return Sodium().aead.xchacha20poly1305ietf }
            func getSign() -> SignType { return Sodium().sign }
            
            func generateBlindingFactor(serverPublicKey: String) -> Bytes? { return nil }
            func blindedKeyPair(serverPublicKey: String, edKeyPair: Box.KeyPair, genericHash: GenericHashType) -> Box.KeyPair? {
                return Box.KeyPair(
                    publicKey: Data.data(fromHex: "7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d")!.bytes,
                    secretKey: Data.data(fromHex: "881132ee03dbd2da065aa4c94f96081f62142dc8011d1b7a00de83e4aab38ce4881132ee03dbd2da065aa4c94f96081f62142dc8011d1b7a00de83e4aab38ce4")!.bytes
                )
            }
            func sogsSignature(message: Bytes, secretKey: Bytes, blindedSecretKey ka: Bytes, blindedPublicKey kA: Bytes) -> Bytes? {
                return nil
            }
            
            func combineKeys(lhsKeyBytes: Bytes, rhsKeyBytes: Bytes) -> Bytes? { return nil }
            func sharedBlindedEncryptionKey(secretKey a: Bytes, otherBlindedPublicKey: Bytes, fromBlindedPublicKey kA: Bytes, toBlindedPublicKey kB: Bytes, genericHash: GenericHashType) -> Bytes? {
                return nil
            }
            
            func sessionId(_ sessionId: String, matchesBlindedId blindedSessionId: String, serverPublicKey: String) -> Bool {
                return false
            }
        }
        testStorage.mockData[.openGroupServer] = OpenGroupAPI.Server(
            name: "testServer",
            capabilities: OpenGroupAPI.Capabilities(capabilities: [.sogs, .blind], missing: [])
        )
        dependencies = dependencies.with(sodium: InvalidSodium())
        
        var response: Any? = nil
        var error: Error? = nil
        
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
    
    func testItFailsToSignIfUnblindedAndTheSignatureDoesNotGetGenerated() throws {
        class InvalidSign: SignType {
            var PublicKeyBytes: Int = 32

            func signature(message: Bytes, secretKey: Bytes) -> Bytes? { return nil }
            func verify(message: Bytes, publicKey: Bytes, signature: Bytes) -> Bool { return false }
            func toX25519(ed25519PublicKey: Bytes) -> Bytes? { return nil }
        }
        testStorage.mockData[.openGroupServer] = OpenGroupAPI.Server(
            name: "testServer",
            capabilities: OpenGroupAPI.Capabilities(capabilities: [.sogs], missing: [])
        )
        dependencies = dependencies.with(sign: InvalidSign())
        
        var response: Any? = nil
        var error: Error? = nil
        
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

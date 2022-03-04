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
        var dependencies: OpenGroupAPI.Dependencies!
        
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
                dependencies = nil
                testStorage = nil
                response = nil
                pollResponse = nil
                error = nil
            }
            
            // MARK: - Batching & Polling
    
            context("when polling") {
                it("generates the correct request") {
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
                    
                    OpenGroupAPI.poll("testServer", using: dependencies)
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
                
                it("errors when no data is returned") {
                    OpenGroupAPI.poll("testServer", using: dependencies)
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
                    
                    OpenGroupAPI.poll("testServer", using: dependencies)
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
                    
                    OpenGroupAPI.poll("testServer", using: dependencies)
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
                    
                    OpenGroupAPI.poll("testServer", using: dependencies)
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
                    
                    OpenGroupAPI.poll("testServer", using: dependencies)
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
                    
                    OpenGroupAPI.poll("testServer", using: dependencies)
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
            
            // MARK: - Files
            
            context("when uploading files") {
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
                    expect(requestData?.urlString).to(equal("testServer/room/testRoom/file"))
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.headers).to(haveCount(6))
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
                    expect(requestData?.urlString).to(equal("testServer/room/testRoom/file"))
                    expect(requestData?.httpMethod).to(equal("POST"))
                    expect(requestData?.headers).to(haveCount(6))
                    expect(requestData?.headers[Header.contentDisposition.rawValue]).to(contain("TestFileName"))
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

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
    
    struct TestNonceGenerator: NonceGenerator16ByteType {
        func nonce() -> Array<UInt8> { return Data(base64Encoded: "pK6YRtQApl4NhECGizF0Cg==")!.bytes }
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
    var dependencies: OpenGroupAPI.Dependencies!

    // MARK: - Configuration
    
    override func setUpWithError() throws {
        testStorage = TestStorage()
        dependencies = OpenGroupAPI.Dependencies(
            api: TestApi.self,
            storage: testStorage,
            nonceGenerator: TestNonceGenerator(),
            date: Date(timeIntervalSince1970: 1234567890)
        )
        
        testStorage.mockData[.allV2OpenGroups] = [
            "0": OpenGroupV2(
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
                            body: OpenGroupAPI.Capabilities(capabilities: [], missing: nil)
                        )
                    ),
                    try! JSONEncoder().encode(
                        OpenGroupAPI.BatchSubResponse(
                            code: 200,
                            headers: [:],
                            body: try! JSONDecoder().decode(OpenGroupAPI.RoomPollInfo.self, from: "{}".data(using: .utf8)!)
                        )
                    ),
                    try! JSONEncoder().encode(
                        OpenGroupAPI.BatchSubResponse(
                            code: 200,
                            headers: [:],
                            body: [OpenGroupAPI.Message]()
                        )
                    )
                ]
                
                return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
            }
        }
        dependencies = dependencies.with(api: LocalTestApi.self)
        
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable)]? = nil
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
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable)]? = nil
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
        
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable)]? = nil
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
        
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable)]? = nil
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
        
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable)]? = nil
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
                            body: OpenGroupAPI.Capabilities(capabilities: [], missing: nil)
                        )
                    ),
                    try! JSONEncoder().encode(
                        OpenGroupAPI.BatchSubResponse(
                            code: 200,
                            headers: [:],
                            body: try! JSONDecoder().decode(OpenGroupAPI.RoomPollInfo.self, from: "{}".data(using: .utf8)!)
                        )
                    )
                ]
                
                return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
            }
        }
        dependencies = dependencies.with(api: LocalTestApi.self)
        
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable)]? = nil
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
                            body: OpenGroupAPI.PinnedMessage(id: 1, pinnedAt: 1, pinnedBy: "")
                        )
                    ),
                    try! JSONEncoder().encode(
                        OpenGroupAPI.BatchSubResponse(
                            code: 200,
                            headers: [:],
                            body: OpenGroupAPI.PinnedMessage(id: 1, pinnedAt: 1, pinnedBy: "")
                        )
                    ),
                    try! JSONEncoder().encode(
                        OpenGroupAPI.BatchSubResponse(
                            code: 200,
                            headers: [:],
                            body: OpenGroupAPI.PinnedMessage(id: 1, pinnedAt: 1, pinnedBy: "")
                        )
                    )
                ]
                
                return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
            }
        }
        dependencies = dependencies.with(api: LocalTestApi.self)
        
        var response: [OpenGroupAPI.Endpoint: (OnionRequestResponseInfoType, Codable)]? = nil
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
    
    func testItSignsTheRequestCorrectly() throws {
        class LocalTestApi: TestApi {
            override class var mockResponse: Data? {
                return try! JSONEncoder().encode([OpenGroupAPI.Room]())
            }
        }
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
        expect(requestData?.headers[Header.sogsPubKey.rawValue]).to(equal("057aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d"))
        expect(requestData?.headers[Header.sogsNonce.rawValue]).to(equal("pK6YRtQApl4NhECGizF0Cg=="))
        expect(requestData?.headers[Header.sogsHash.rawValue]).to(equal("fxqLy5ZDWCsLQpwLw0Dax+4xe7cG2vPRk1NlHORIm0DPd3o9UA24KLZY"))
        expect(requestData?.headers[Header.sogsTimestamp.rawValue]).to(equal("1234567890"))
    }
    
    func testItFailsToSignIfTheServerPublicKeyIsInvalid() throws {
        testStorage.mockData[.openGroupPublicKeys] = ["testServer": ""]
        
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
    
    func testItFailsToSignIfThereIsNoUserKeyPair() throws {
        testStorage.mockData[.userKeyPair] = nil
        
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
    
    func testItFailsToSignIfTheSharedSecretDoesNotGetGenerated() throws {
        class InvalidSodium: SodiumType {
            func getGenericHash() -> GenericHashType { return Sodium().genericHash }
            func sharedSecret(_ firstKeyBytes: [UInt8], _ secondKeyBytes: [UInt8]) -> Sodium.SharedSecret? { return nil }
        }
        
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
    
    func testItFailsToSignIfTheIntermediateHashDoesNotGetGenerated() throws {
        class InvalidGenericHash: GenericHashType {
            func hashSaltPersonal(message: Bytes, outputLength: Int, key: Bytes?, salt: Bytes, personal: Bytes) -> Bytes? {
                return nil
            }
        }
        
        dependencies = dependencies.with(genericHash: InvalidGenericHash())
        
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
    
    func testItFailsToSignIfTheSecretHashDoesNotGetGenerated() throws {
        class InvalidSecondGenericHash: GenericHashType {
            static var didSucceedOnce: Bool = false
            
            func hashSaltPersonal(message: Bytes, outputLength: Int, key: Bytes?, salt: Bytes, personal: Bytes) -> Bytes? {
                if !InvalidSecondGenericHash.didSucceedOnce {
                    InvalidSecondGenericHash.didSucceedOnce = true
                    return Data().bytes
                }
                
                return nil
            }
        }
        
        dependencies = dependencies.with(genericHash: InvalidSecondGenericHash())
        
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

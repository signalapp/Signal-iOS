// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import XCTest
import Nimble
import PromiseKit
import SessionSnodeKit

@testable import SessionMessagingKit

class OpenGroupAPIV2Tests: XCTestCase {
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

    // MARK: - Configuration
    
    override func setUpWithError() throws {
        testStorage = TestStorage()
        
        testStorage.mockData[.allV2OpenGroups] = [
            "0": OpenGroupV2(server: "testServer", room: "test1", name: "Test", publicKey: "7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d", imageID: nil)
        ]
        testStorage.mockData[.openGroupPublicKeys] = ["testServer": "7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d"]
        
        // Test Private key, not actually used (from here https://www.notion.so/oxen/SOGS-Authentication-dc64cc846cb24b2abbf7dd4bfd74abbb)
        testStorage.mockData[.userKeyPair] = try! ECKeyPair(
            publicKeyData: Data.data(fromHex: "7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d")!,
            privateKeyData: Data.data(fromHex: "881132ee03dbd2da065aa4c94f96081f62142dc8011d1b7a00de83e4aab38ce4")!
        )
    }

    override func tearDownWithError() throws {
        testStorage = nil
    }
    
    // MARK: - Batching & Polling
    
    func testPollGeneratesTheCorrectRequest() throws {
        // Define a custom TestApi class so we can override the response
        class TestApi1: TestApi {
            override class var mockResponse: Data? {
                let responses: [Data] = [
                    try! JSONEncoder().encode(
                        OpenGroupAPIV2.BatchSubResponse(
                            code: 200,
                            headers: [:],
                            body: OpenGroupAPIV2.Capabilities(capabilities: [], missing: nil)
                        )
                    ),
                    try! JSONEncoder().encode(
                        OpenGroupAPIV2.BatchSubResponse(
                            code: 200,
                            headers: [:],
                            body: OpenGroupAPIV2.RoomPollInfo(
                                token: nil,
                                created: nil,
                                name: nil,
                                description: nil,
                                imageId: nil,
                                
                                infoUpdates: nil,
                                messageSequence: nil,
                                activeUsers: nil,
                                activeUsersCutoff: nil,
                                pinnedMessages: nil,
                                
                                admin: nil,
                                globalAdmin: nil,
                                admins: nil,
                                hiddenAdmins: nil,
                                
                                moderator: nil,
                                globalModerator: nil,
                                moderators: nil,
                                hiddenModerators: nil,
                                read: nil,
                                defaultRead: nil,
                                write: nil,
                                defaultWrite: nil,
                                upload: nil,
                                defaultUpload: nil,
                                details: nil
                            )
                        )
                    ),
                    try! JSONEncoder().encode(
                        OpenGroupAPIV2.BatchSubResponse(
                            code: 200,
                            headers: [:],
                            body: [OpenGroupAPIV2.Message]()
                        )
                    )
                ]
                
                return "[\(responses.map { String(data: $0, encoding: .utf8)! }.joined(separator: ","))]".data(using: .utf8)
            }
        }
        
        var pollResponse: [Endpoint: (OnionRequestResponseInfoType, Codable)]? = nil
        
        OpenGroupAPIV2.poll("testServer", through: TestApi1.self, using: testStorage, nonceGenerator: TestNonceGenerator(), date: Date(timeIntervalSince1970: 1234567890))
            .map { result -> [Endpoint: (OnionRequestResponseInfoType, Codable)] in
                pollResponse = result
                return result
            }
            .retainUntilComplete()
        
        expect(pollResponse)
            .toEventuallyNot(
                beNil(),
                timeout: .milliseconds(10000)
            )
        
        // Validate the response data
        expect(pollResponse?.values).to(haveCount(3))
        expect(pollResponse?.keys).to(contain(.capabilities))
        expect(pollResponse?.keys).to(contain(.roomPollInfo("test1", 0)))
        expect(pollResponse?.keys).to(contain(.roomMessagesRecent("test1")))
        expect(pollResponse?[.capabilities]?.0).to(beAKindOf(TestResponseInfo.self))
        
        // Validate request data
        let requestData: TestApi.RequestData? = (pollResponse?[.capabilities]?.0 as? TestResponseInfo)?.requestData
        expect(requestData?.urlString).to(equal("testServer/batch"))
        expect(requestData?.httpMethod).to(equal("POST"))
        expect(requestData?.server).to(equal("testServer"))
        expect(requestData?.publicKey).to(equal("7aecdcade88d881d2327ab011afd2e04c2ec6acffc9e9df45aaf78a151bd2f7d"))
    }
    
    // MARK: - Authentication
    
    func testItSignsTheRequestCorrectly() throws {
        class TestApi1: TestApi {
            override class var mockResponse: Data? {
                return try! JSONEncoder().encode([OpenGroupAPIV2.Room]())
            }
        }
        
        var response: (OnionRequestResponseInfoType, [OpenGroupAPIV2.Room])? = nil
        
        OpenGroupAPIV2.rooms(for: "testServer", through: TestApi1.self, using: testStorage, nonceGenerator: TestNonceGenerator(), date: Date(timeIntervalSince1970: 1234567890))
            .map { result -> (OnionRequestResponseInfoType, [OpenGroupAPIV2.Room]) in
                response = result
                return result
            }
            .retainUntilComplete()
        
        expect(response)
            .toEventuallyNot(
                beNil(),
                timeout: .milliseconds(10000)
            )
        
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
}

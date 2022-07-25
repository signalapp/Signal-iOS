// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

import Quick
import Nimble

@testable import SessionMessagingKit
import AVFoundation

class BatchRequestInfoSpec: QuickSpec {
    struct TestType: Codable, Equatable {
        let stringValue: String
    }
    
    // MARK: - Spec

    override func spec() {
        // MARK: - BatchSubRequest
        
        describe("a BatchSubRequest") {
            var subRequest: OpenGroupAPI.BatchSubRequest!
            
            context("when initializing") {
                it("sets the headers to nil if there aren't any") {
                    subRequest = OpenGroupAPI.BatchSubRequest(
                        request: Request<NoBody, OpenGroupAPI.Endpoint>(
                            server: "testServer",
                            endpoint: .batch
                        )
                    )
                    
                    expect(subRequest.headers).to(beNil())
                }
                
                it("converts the headers to HTTP headers") {
                    subRequest = OpenGroupAPI.BatchSubRequest(
                        request: Request<NoBody, OpenGroupAPI.Endpoint>(
                            method: .get,
                            server: "testServer",
                            endpoint: .batch,
                            queryParameters: [:],
                            headers: [.authorization: "testAuth"],
                            body: nil
                        )
                    )
                    
                    expect(subRequest.headers).to(equal(["Authorization": "testAuth"]))
                }
            }
            
            context("when encoding") {
                it("successfully encodes a string body") {
                    subRequest = OpenGroupAPI.BatchSubRequest(
                        request: Request<String, OpenGroupAPI.Endpoint>(
                            method: .get,
                            server: "testServer",
                            endpoint: .batch,
                            queryParameters: [:],
                            headers: [:],
                            body: "testBody"
                        )
                    )
                    let subRequestData: Data = try! JSONEncoder().encode(subRequest)
                    let subRequestString: String? = String(data: subRequestData, encoding: .utf8)
                    
                    expect(subRequestString)
                        .to(equal("{\"path\":\"\\/batch\",\"method\":\"GET\",\"b64\":\"testBody\"}"))
                }
                
                it("successfully encodes a byte body") {
                    subRequest = OpenGroupAPI.BatchSubRequest(
                        request: Request<[UInt8], OpenGroupAPI.Endpoint>(
                            method: .get,
                            server: "testServer",
                            endpoint: .batch,
                            queryParameters: [:],
                            headers: [:],
                            body: [1, 2, 3]
                        )
                    )
                    let subRequestData: Data = try! JSONEncoder().encode(subRequest)
                    let subRequestString: String? = String(data: subRequestData, encoding: .utf8)
                    
                    expect(subRequestString)
                        .to(equal("{\"path\":\"\\/batch\",\"method\":\"GET\",\"bytes\":[1,2,3]}"))
                }
                
                it("successfully encodes a JSON body") {
                    subRequest = OpenGroupAPI.BatchSubRequest(
                        request: Request<TestType, OpenGroupAPI.Endpoint>(
                            method: .get,
                            server: "testServer",
                            endpoint: .batch,
                            queryParameters: [:],
                            headers: [:],
                            body: TestType(stringValue: "testValue")
                        )
                    )
                    let subRequestData: Data = try! JSONEncoder().encode(subRequest)
                    let subRequestString: String? = String(data: subRequestData, encoding: .utf8)
                    
                    expect(subRequestString)
                        .to(equal("{\"path\":\"\\/batch\",\"method\":\"GET\",\"json\":{\"stringValue\":\"testValue\"}}"))
                }
            }
        }
        
        // MARK: - BatchSubResponse<T>
        
        describe("a BatchSubResponse<T>") {
            context("when decoding") {
                it("decodes correctly") {
                    let jsonString: String = """
                    {
                        "code": 200,
                        "headers": {
                            "testKey": "testValue"
                        },
                        "body": {
                            "stringValue": "testValue"
                        }
                    }
                    """
                    let subResponse: OpenGroupAPI.BatchSubResponse<TestType>? = try? JSONDecoder().decode(
                        OpenGroupAPI.BatchSubResponse<TestType>.self,
                        from: jsonString.data(using: .utf8)!
                    )
                    
                    expect(subResponse).toNot(beNil())
                    expect(subResponse?.body).toNot(beNil())
                }
                
                it("decodes with invalid body data") {
                    let jsonString: String = """
                    {
                        "code": 200,
                        "headers": {
                            "testKey": "testValue"
                        },
                        "body": "Hello!!!"
                    }
                    """
                    let subResponse: OpenGroupAPI.BatchSubResponse<TestType>? = try? JSONDecoder().decode(
                        OpenGroupAPI.BatchSubResponse<TestType>.self,
                        from: jsonString.data(using: .utf8)!
                    )
                    
                    expect(subResponse).toNot(beNil())
                }
                
                it("flags invalid body data as invalid") {
                    let jsonString: String = """
                    {
                        "code": 200,
                        "headers": {
                            "testKey": "testValue"
                        },
                        "body": "Hello!!!"
                    }
                    """
                    let subResponse: OpenGroupAPI.BatchSubResponse<TestType>? = try? JSONDecoder().decode(
                        OpenGroupAPI.BatchSubResponse<TestType>.self,
                        from: jsonString.data(using: .utf8)!
                    )
                    
                    expect(subResponse).toNot(beNil())
                    expect(subResponse?.body).to(beNil())
                    expect(subResponse?.failedToParseBody).to(beTrue())
                }
                
                it("does not flag a missing or invalid optional body as invalid") {
                    let jsonString: String = """
                    {
                        "code": 200,
                        "headers": {
                            "testKey": "testValue"
                        },
                    }
                    """
                    let subResponse: OpenGroupAPI.BatchSubResponse<TestType?>? = try? JSONDecoder().decode(
                        OpenGroupAPI.BatchSubResponse<TestType?>.self,
                        from: jsonString.data(using: .utf8)!
                    )
                    
                    expect(subResponse).toNot(beNil())
                    expect(subResponse?.body).to(beNil())
                    expect(subResponse?.failedToParseBody).to(beFalse())
                }
                
                it("does not flag a NoResponse body as invalid") {
                    let jsonString: String = """
                    {
                        "code": 200,
                        "headers": {
                            "testKey": "testValue"
                        },
                    }
                    """
                    let subResponse: OpenGroupAPI.BatchSubResponse<NoResponse>? = try? JSONDecoder().decode(
                        OpenGroupAPI.BatchSubResponse<NoResponse>.self,
                        from: jsonString.data(using: .utf8)!
                    )
                    
                    expect(subResponse).toNot(beNil())
                    expect(subResponse?.body).to(beNil())
                    expect(subResponse?.failedToParseBody).to(beFalse())
                }
            }
        }
        
        // MARK: - BatchRequestInfo<T, R>
        
        describe("a BatchRequestInfo<T, R>") {
            var request: Request<TestType, OpenGroupAPI.Endpoint>!
            
            beforeEach {
                request = Request(
                    method: .get,
                    server: "testServer",
                    endpoint: .batch,
                    queryParameters: [:],
                    headers: [:],
                    body: TestType(stringValue: "testValue")
                )
            }
            
            it("initializes correctly when given a request") {
                let requestInfo: OpenGroupAPI.BatchRequestInfo<TestType> = OpenGroupAPI.BatchRequestInfo(
                    request: request
                )
                
                expect(requestInfo.request).to(equal(request))
                expect(requestInfo.responseType == OpenGroupAPI.BatchSubResponse<NoResponse>.self).to(beTrue())
            }
            
            it("initializes correctly when given a request and a response type") {
                let requestInfo: OpenGroupAPI.BatchRequestInfo<TestType> = OpenGroupAPI.BatchRequestInfo(
                    request: request,
                    responseType: TestType.self
                )
                
                expect(requestInfo.request).to(equal(request))
                expect(requestInfo.responseType == OpenGroupAPI.BatchSubResponse<TestType>.self).to(beTrue())
            }
            
            it("exposes the endpoint correctly") {
                let requestInfo: OpenGroupAPI.BatchRequestInfo<TestType> = OpenGroupAPI.BatchRequestInfo(
                    request: request
                )
                
                expect(requestInfo.endpoint.path).to(equal(request.endpoint.path))
            }
            
            it("generates a sub request correctly") {
                let requestInfo: OpenGroupAPI.BatchRequestInfo<TestType> = OpenGroupAPI.BatchRequestInfo(
                    request: request
                )
                let subRequest: OpenGroupAPI.BatchSubRequest = requestInfo.toSubRequest()
                
                expect(subRequest.method).to(equal(request.method))
                expect(subRequest.path).to(equal(request.urlPathAndParamsString))
                expect(subRequest.headers).to(beNil())
            }
        }
        
        // MARK: - Convenience
        // MARK: --Decodable
        
        describe("a Decodable") {
            it("decodes correctly") {
                let jsonData: Data = "{\"stringValue\":\"testValue\"}".data(using: .utf8)!
                let result: TestType? = try? TestType.decoded(from: jsonData)
                
                expect(result).to(equal(TestType(stringValue: "testValue")))
            }
        }
        
        // MARK: - --Promise
        
        describe("an (OnionRequestResponseInfoType, Data?) Promise") {
            var responseInfo: OnionRequestResponseInfoType!
            var capabilities: OpenGroupAPI.Capabilities!
            var pinnedMessage: OpenGroupAPI.PinnedMessage!
            var data: Data!
            
            beforeEach {
                responseInfo = OnionRequestAPI.ResponseInfo(code: 200, headers: [:])
                capabilities = OpenGroupAPI.Capabilities(capabilities: [], missing: nil)
                pinnedMessage = OpenGroupAPI.PinnedMessage(id: 1, pinnedAt: 123, pinnedBy: "test")
                data = """
                [\([
                    try! JSONEncoder().encode(
                        OpenGroupAPI.BatchSubResponse(
                            code: 200,
                            headers: [:],
                            body: capabilities,
                            failedToParseBody: false
                        )
                    ),
                    try! JSONEncoder().encode(
                        OpenGroupAPI.BatchSubResponse(
                            code: 200,
                            headers: [:],
                            body: pinnedMessage,
                            failedToParseBody: false
                        )
                    )
                ]
                .map { String(data: $0, encoding: .utf8)! }
                .joined(separator: ","))]
                """.data(using: .utf8)!
            }
            
            it("decodes valid data correctly") {
                let result = Promise.value((responseInfo, data))
                    .decoded(as: [
                        OpenGroupAPI.BatchSubResponse<OpenGroupAPI.Capabilities>.self,
                        OpenGroupAPI.BatchSubResponse<OpenGroupAPI.PinnedMessage>.self
                    ])
                
                expect(result.value).toNot(beNil())
                expect((result.value?[0].1 as? OpenGroupAPI.BatchSubResponse<OpenGroupAPI.Capabilities>)?.body)
                    .to(equal(capabilities))
                expect((result.value?[1].1 as? OpenGroupAPI.BatchSubResponse<OpenGroupAPI.PinnedMessage>)?.body)
                    .to(equal(pinnedMessage))
            }
            
            it("fails if there is no data") {
                let result = Promise.value((responseInfo, nil)).decoded(as: [])
                
                expect(result.error?.localizedDescription).to(equal(HTTP.Error.parsingFailed.localizedDescription))
            }
            
            it("fails if the data is not JSON") {
                let result = Promise.value((responseInfo, Data([1, 2, 3]))).decoded(as: [])
                
                expect(result.error?.localizedDescription).to(equal(HTTP.Error.parsingFailed.localizedDescription))
            }
            
            it("fails if the data is not a JSON array") {
                let result = Promise.value((responseInfo, "{}".data(using: .utf8))).decoded(as: [])
                
                expect(result.error?.localizedDescription).to(equal(HTTP.Error.parsingFailed.localizedDescription))
            }
            
            it("fails if the JSON array does not have the same number of items as the expected types") {
                let result = Promise.value((responseInfo, data))
                    .decoded(as: [
                        OpenGroupAPI.BatchSubResponse<OpenGroupAPI.Capabilities>.self,
                        OpenGroupAPI.BatchSubResponse<OpenGroupAPI.PinnedMessage>.self,
                        OpenGroupAPI.BatchSubResponse<OpenGroupAPI.PinnedMessage>.self
                    ])
                
                expect(result.error?.localizedDescription).to(equal(HTTP.Error.parsingFailed.localizedDescription))
            }
            
            it("fails if one of the JSON array values fails to decode") {
                data = """
                [\([
                    try! JSONEncoder().encode(
                        OpenGroupAPI.BatchSubResponse(
                            code: 200,
                            headers: [:],
                            body: capabilities,
                            failedToParseBody: false
                        )
                    )
                ]
                .map { String(data: $0, encoding: .utf8)! }
                .joined(separator: ",")),{"test": "test"}]
                """.data(using: .utf8)!
                let result = Promise.value((responseInfo, data))
                    .decoded(as: [
                        OpenGroupAPI.BatchSubResponse<OpenGroupAPI.Capabilities>.self,
                        OpenGroupAPI.BatchSubResponse<OpenGroupAPI.PinnedMessage>.self
                    ])
                
                expect(result.error?.localizedDescription).to(equal(HTTP.Error.parsingFailed.localizedDescription))
            }
        }
    }
}

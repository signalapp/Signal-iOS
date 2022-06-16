// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble
import SessionUtilitiesKit

@testable import SessionMessagingKit

class RequestSpec: QuickSpec {
    struct TestType: Codable, Equatable {
        let stringValue: String
    }
    
    // MARK: - Spec

    override func spec() {
        describe("a Request") {
            it("is initialized with the correct default values") {
                let request: Request<NoBody, OpenGroupAPI.Endpoint> = Request(
                    server: "testServer",
                    endpoint: .batch
                )
                
                expect(request.method.rawValue).to(equal("GET"))
                expect(request.queryParameters).to(equal([:]))
                expect(request.headers).to(equal([:]))
                expect(request.body).to(beNil())
            }
            
            context("when generating a URL") {
                it("adds a leading forward slash to the endpoint path") {
                    let request: Request<NoBody, OpenGroupAPI.Endpoint> = Request(
                        server: "testServer",
                        endpoint: .batch
                    )
                    
                    expect(request.urlPathAndParamsString).to(equal("/batch"))
                }
                
                it("creates a valid URL with no query parameters") {
                    let request: Request<NoBody, OpenGroupAPI.Endpoint> = Request(
                        server: "testServer",
                        endpoint: .batch
                    )
                    
                    expect(request.urlPathAndParamsString).to(equal("/batch"))
                }
                
                it("creates a valid URL when query parameters are provided") {
                    let request: Request<NoBody, OpenGroupAPI.Endpoint> = Request(
                        server: "testServer",
                        endpoint: .batch,
                        queryParameters: [
                            .limit: "123"
                        ]
                    )
                    
                    expect(request.urlPathAndParamsString).to(equal("/batch?limit=123"))
                }
            }
            
            context("when generating a URLRequest") {
                it("sets all the values correctly") {
                    let request: Request<NoBody, OpenGroupAPI.Endpoint> = Request(
                        method: .delete,
                        server: "testServer",
                        endpoint: .batch,
                        headers: [
                            .authorization: "test"
                        ]
                    )
                    let urlRequest: URLRequest? = try? request.generateUrlRequest()
                    
                    expect(urlRequest?.httpMethod).to(equal("DELETE"))
                    expect(urlRequest?.allHTTPHeaderFields).to(equal(["Authorization": "test"]))
                    expect(urlRequest?.httpBody).to(beNil())
                }
                
                it("throws an error if the URL is invalid") {
                    let request: Request<NoBody, OpenGroupAPI.Endpoint> = Request(
                        server: "testServer",
                        endpoint: .roomPollInfo("!!%%", 123)
                    )
                    
                    expect {
                        try request.generateUrlRequest()
                    }
                    .to(throwError(HTTP.Error.invalidURL))
                }
                
                context("with a base64 string body") {
                    it("successfully encodes the body") {
                        let request: Request<String, OpenGroupAPI.Endpoint> = Request(
                            server: "testServer",
                            endpoint: .batch,
                            body: "TestMessage".data(using: .utf8)!.base64EncodedString()
                        )
                        
                        let urlRequest: URLRequest? = try? request.generateUrlRequest()
                        let requestBody: Data? = Data(base64Encoded: urlRequest?.httpBody?.base64EncodedString() ?? "")
                        let requestBodyString: String? = String(data: requestBody ?? Data(), encoding: .utf8)
                        
                        expect(requestBodyString).to(equal("TestMessage"))
                    }
                    
                    it("throws an error if the body is not base64 encoded") {
                        let request: Request<String, OpenGroupAPI.Endpoint> = Request(
                            server: "testServer",
                            endpoint: .batch,
                            body: "TestMessage"
                        )
                        
                        expect {
                            try request.generateUrlRequest()
                        }
                        .to(throwError(HTTP.Error.parsingFailed))
                    }
                }
                
                context("with a byte body") {
                    it("successfully encodes the body") {
                        let request: Request<[UInt8], OpenGroupAPI.Endpoint> = Request(
                            server: "testServer",
                            endpoint: .batch,
                            body: [1, 2, 3]
                        )
                        
                        let urlRequest: URLRequest? = try? request.generateUrlRequest()
                        
                        expect(urlRequest?.httpBody?.bytes).to(equal([1, 2, 3]))
                    }
                }
                
                context("with a JSON body") {
                    it("successfully encodes the body") {
                        let request: Request<TestType, OpenGroupAPI.Endpoint> = Request(
                            server: "testServer",
                            endpoint: .batch,
                            body: TestType(stringValue: "test")
                        )
                        
                        let urlRequest: URLRequest? = try? request.generateUrlRequest()
                        let requestBody: TestType? = try? JSONDecoder().decode(
                            TestType.self,
                            from: urlRequest?.httpBody ?? Data()
                        )
                        
                        expect(requestBody).to(equal(TestType(stringValue: "test")))
                    }
                    
                    it("successfully encodes no body") {
                        let request: Request<NoBody, OpenGroupAPI.Endpoint> = Request(
                            server: "testServer",
                            endpoint: .batch,
                            body: nil
                        )
                        
                        expect {
                            try request.generateUrlRequest()
                        }.toNot(throwError())
                    }
                }
            }
        }
    }
}

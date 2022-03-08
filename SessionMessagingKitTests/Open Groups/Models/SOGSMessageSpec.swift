// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class SOGSMessageSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("a SOGSMessage") {
            var messageJson: String!
            var messageData: Data!
            var decoder: JSONDecoder!
            var testSign: TestSign!
            var dependencies: Dependencies!
            
            beforeEach {
                messageJson = """
                {
                    "id": 123,
                    "session_id": "05\(TestConstants.publicKey)",
                    "posted": 234,
                    "seqno": 345,
                    "whisper": false,
                    "whisper_mods": false,
                            
                    "data": "VGVzdERhdGE=",
                    "signature": "VGVzdERhdGE="
                }
                """
                messageData = messageJson.data(using: .utf8)!
                testSign = TestSign()
                dependencies = Dependencies(
                    sign: testSign,
                    ed25519: TestEd25519.self
                )
                decoder = JSONDecoder()
                decoder.userInfo = [ Dependencies.userInfoKey: dependencies as Any ]
            }
            
            context("when decoding") {
                it("defaults the whisper values to false") {
                    messageJson = """
                    {
                        "id": 123,
                        "posted": 234,
                        "seqno": 345
                    }
                    """
                    messageData = messageJson.data(using: .utf8)!
                    let result: OpenGroupAPI.Message? = try? decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                    
                    expect(result).toNot(beNil())
                    expect(result?.whisper).to(beFalse())
                    expect(result?.whisperMods).to(beFalse())
                }
                
                context("and there is no content") {
                    it("does not need a sender") {
                        messageJson = """
                        {
                            "id": 123,
                            "posted": 234,
                            "seqno": 345,
                            "whisper": false,
                            "whisper_mods": false
                        }
                        """
                        messageData = messageJson.data(using: .utf8)!
                        let result: OpenGroupAPI.Message? = try? decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                        
                        expect(result).toNot(beNil())
                        expect(result?.sender).to(beNil())
                        expect(result?.base64EncodedData).to(beNil())
                        expect(result?.base64EncodedSignature).to(beNil())
                    }
                }
                
                context("and there is content") {
                    it("errors if there is no sender") {
                        messageJson = """
                        {
                            "id": 123,
                            "posted": 234,
                            "seqno": 345,
                            "whisper": false,
                            "whisper_mods": false,
                        
                            "data": "VGVzdERhdGE=",
                            "signature": "VGVzdERhdGE="
                        }
                        """
                        messageData = messageJson.data(using: .utf8)!
                        
                        expect {
                            try decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                        }
                        .to(throwError(HTTP.Error.parsingFailed))
                    }
                    
                    it("errors if the data is not a base64 encoded string") {
                        messageJson = """
                        {
                            "id": 123,
                            "session_id": "05\(TestConstants.publicKey)",
                            "posted": 234,
                            "seqno": 345,
                            "whisper": false,
                            "whisper_mods": false,
                        
                            "data": "Test!!!",
                            "signature": "VGVzdERhdGE="
                        }
                        """
                        messageData = messageJson.data(using: .utf8)!
                        
                        expect {
                            try decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                        }
                        .to(throwError(HTTP.Error.parsingFailed))
                    }
                    
                    it("errors if the signature is not a base64 encoded string") {
                        messageJson = """
                        {
                            "id": 123,
                            "session_id": "05\(TestConstants.publicKey)",
                            "posted": 234,
                            "seqno": 345,
                            "whisper": false,
                            "whisper_mods": false,
                        
                            "data": "VGVzdERhdGE=",
                            "signature": "Test!!!"
                        }
                        """
                        messageData = messageJson.data(using: .utf8)!
                        
                        expect {
                            try decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                        }
                        .to(throwError(HTTP.Error.parsingFailed))
                    }
                    
                    it("errors if the dependencies are not provided to the JSONDecoder") {
                        decoder = JSONDecoder()
                        
                        expect {
                            try decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                        }
                        .to(throwError(HTTP.Error.parsingFailed))
                    }
                    
                    it("errors if the session_id value is not valid") {
                        messageJson = """
                        {
                            "id": 123,
                            "session_id": "TestId",
                            "posted": 234,
                            "seqno": 345,
                            "whisper": false,
                            "whisper_mods": false,
                        
                            "data": "VGVzdERhdGE=",
                            "signature": "VGVzdERhdGE="
                        }
                        """
                        messageData = messageJson.data(using: .utf8)!
                        
                        expect {
                            try decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                        }
                        .to(throwError(HTTP.Error.parsingFailed))
                    }
                    
                    
                    context("that is blinded") {
                        beforeEach {
                            messageJson = """
                            {
                                "id": 123,
                                "session_id": "15\(TestConstants.publicKey)",
                                "posted": 234,
                                "seqno": 345,
                                "whisper": false,
                                "whisper_mods": false,
                                        
                                "data": "VGVzdERhdGE=",
                                "signature": "VGVzdERhdGE="
                            }
                            """
                            messageData = messageJson.data(using: .utf8)!
                        }
                        
                        it("succeeds if it succeeds verification") {
                            testSign.mockData[.verify] = true
                            
                            expect {
                                try decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                            }
                            .toNot(beNil())
                        }
                        
                        it("throws if it fails verification") {
                            testSign.mockData[.verify] = false
                            
                            expect {
                                try decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                            }
                            .to(throwError(HTTP.Error.parsingFailed))
                        }
                    }
                    
                    context("that is unblinded") {
                        it("succeeds if it succeeds verification") {
                            TestEd25519.mockData[
                                .verifySignature(
                                    signature: Data(base64Encoded: "VGVzdERhdGE=")!,
                                    publicKey: Data(hex: TestConstants.publicKey),
                                    data: Data(base64Encoded: "VGVzdERhdGE=")!
                                )
                            ] = true
                            
                            expect {
                                try decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                            }
                            .toNot(beNil())
                        }
                        
                        it("throws if it fails verification") {
                            TestEd25519.mockData[
                                .verifySignature(
                                    signature: Data(base64Encoded: "VGVzdERhdGE=")!,
                                    publicKey: Data(hex: TestConstants.publicKey),
                                    data: Data(base64Encoded: "VGVzdERhdGE=")!
                                )
                            ] = false
                            
                            expect {
                                try decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                            }
                            .to(throwError(HTTP.Error.parsingFailed))
                        }
                    }
                }
            }
        }
    }
}

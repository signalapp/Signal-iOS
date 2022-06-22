// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble
import SessionUtilitiesKit

@testable import SessionMessagingKit

class SOGSMessageSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("a SOGSMessage") {
            var messageJson: String!
            var messageData: Data!
            var decoder: JSONDecoder!
            var mockSign: MockSign!
            var mockEd25519: MockEd25519!
            var dependencies: SMKDependencies!
            
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
                    "signature": "VGVzdFNpZ25hdHVyZQ=="
                }
                """
                messageData = messageJson.data(using: .utf8)!
                mockSign = MockSign()
                mockEd25519 = MockEd25519()
                dependencies = SMKDependencies(
                    sign: mockSign,
                    ed25519: mockEd25519
                )
                decoder = JSONDecoder()
                decoder.userInfo = [ Dependencies.userInfoKey: dependencies as Any ]
            }
            
            afterEach {
                mockSign = nil
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
                            "signature": "VGVzdFNpZ25hdHVyZQ=="
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
                            "signature": "VGVzdFNpZ25hdHVyZQ=="
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
                            "signature": "VGVzdFNpZ25hdHVyZQ=="
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
                                "signature": "VGVzdFNpZ25hdHVyZQ=="
                            }
                            """
                            messageData = messageJson.data(using: .utf8)!
                        }
                        
                        it("succeeds if it succeeds verification") {
                            mockSign
                                .when { $0.verify(message: anyArray(), publicKey: anyArray(), signature: anyArray()) }
                                .thenReturn(true)
                            
                            expect {
                                try decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                            }
                            .toNot(beNil())
                        }
                        
                        it("provides the correct values as parameters") {
                            mockSign
                                .when { $0.verify(message: anyArray(), publicKey: anyArray(), signature: anyArray()) }
                                .thenReturn(true)
                            
                            _ = try? decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                            
                            expect(mockSign)
                                .to(call(matchingParameters: true) {
                                    $0.verify(
                                        message: Data(base64Encoded: "VGVzdERhdGE=")!.bytes,
                                        publicKey: Data(hex: TestConstants.publicKey).bytes,
                                        signature: Data(base64Encoded: "VGVzdFNpZ25hdHVyZQ==")!.bytes
                                    )
                                })
                        }
                        
                        it("throws if it fails verification") {
                            mockSign
                                .when { $0.verify(message: anyArray(), publicKey: anyArray(), signature: anyArray()) }
                                .thenReturn(false)
                            
                            expect {
                                try decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                            }
                            .to(throwError(HTTP.Error.parsingFailed))
                        }
                    }
                    
                    context("that is unblinded") {
                        it("succeeds if it succeeds verification") {
                            mockEd25519.when { try $0.verifySignature(any(), publicKey: any(), data: any()) }.thenReturn(true)
                            
                            expect {
                                try decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                            }
                            .toNot(beNil())
                        }
                        
                        it("provides the correct values as parameters") {
                            mockEd25519.when { try $0.verifySignature(any(), publicKey: any(), data: any()) }.thenReturn(true)
                            
                            _ = try? decoder.decode(OpenGroupAPI.Message.self, from: messageData)
                            
                            expect(mockEd25519)
                                .to(call(matchingParameters: true) {
                                    try $0.verifySignature(
                                        Data(base64Encoded: "VGVzdFNpZ25hdHVyZQ==")!,
                                        publicKey: Data(hex: TestConstants.publicKey),
                                        data: Data(base64Encoded: "VGVzdERhdGE=")!
                                    )
                                })
                        }
                        
                        it("throws if it fails verification") {
                            mockEd25519.when { try $0.verifySignature(any(), publicKey: any(), data: any()) }.thenReturn(false)
                            
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

// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class OpenGroupSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("an Open Group") {
            context("when initializing") {
                it("generates the id") {
                    let openGroup: OpenGroup = OpenGroup(
                        server: "server",
                        roomToken: "room",
                        publicKey: "1234",
                        isActive: true,
                        name: "name",
                        roomDescription: nil,
                        imageId: nil,
                        imageData: nil,
                        userCount: 0,
                        infoUpdates: 0,
                        sequenceNumber: 0,
                        inboxLatestMessageId: 0,
                        outboxLatestMessageId: 0
                    )
                    
                    expect(openGroup.id).to(equal("server.room"))
                }
            }
            
            context("when describing") {
                it("includes relevant information") {
                    let openGroup: OpenGroup = OpenGroup(
                        server: "server",
                        roomToken: "room",
                        publicKey: "1234",
                        isActive: true,
                        name: "name",
                        roomDescription: nil,
                        imageId: nil,
                        imageData: nil,
                        userCount: 0,
                        infoUpdates: 0,
                        sequenceNumber: 0,
                        inboxLatestMessageId: 0,
                        outboxLatestMessageId: 0
                    )
                    
                    expect(openGroup.description)
                        .to(equal("name (Server: server, Room: room)"))
                }
            }
            
            context("when describing in debug") {
                it("includes relevant information") {
                    let openGroup: OpenGroup = OpenGroup(
                        server: "server",
                        roomToken: "room",
                        publicKey: "1234",
                        isActive: true,
                        name: "name",
                        roomDescription: nil,
                        imageId: nil,
                        imageData: nil,
                        userCount: 0,
                        infoUpdates: 0,
                        sequenceNumber: 0,
                        inboxLatestMessageId: 0,
                        outboxLatestMessageId: 0
                    )
                    
                    expect(openGroup.debugDescription)
                        .to(equal("OpenGroup(server: \"server\", roomToken: \"room\", id: \"server.room\", publicKey: \"1234\", isActive: true, name: \"name\", roomDescription: null, imageId: null, userCount: 0, infoUpdates: 0, sequenceNumber: 0, inboxLatestMessageId: 0, outboxLatestMessageId: 0, pollFailureCount: 0, permissions: ---)"))
                }
            }
            
            context("when generating an id") {
                it("generates correctly") {
                    expect(OpenGroup.idFor(roomToken: "room", server: "server")).to(equal("server.room"))
                }
                
                it("converts the server to lowercase") {
                    expect(OpenGroup.idFor(roomToken: "room", server: "SeRVeR")).to(equal("server.room"))
                }
                
                it("maintains the casing of the roomToken") {
                    expect(OpenGroup.idFor(roomToken: "RoOM", server: "server")).to(equal("server.RoOM"))
                }
            }
            
            context("when generating a url") {
                it("generates the url correctly") {
                    expect(OpenGroup.urlFor(server: "server", roomToken: "room", publicKey: "key"))
                        .to(equal("server/room?public_key=key"))
                }
                
                it("maintains the casing provided") {
                    expect(OpenGroup.urlFor(server: "SeRVer", roomToken: "RoOM", publicKey: "KEy"))
                        .to(equal("SeRVer/RoOM?public_key=KEy"))
                }
            }
        }
    }
}

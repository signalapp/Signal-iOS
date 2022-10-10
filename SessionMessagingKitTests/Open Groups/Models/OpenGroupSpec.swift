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
        }
    }
}

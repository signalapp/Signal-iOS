// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class SOGSEndpointSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("a SOGSEndpoint") {
            it("generates the path value correctly") {
                // Utility
                
                expect(OpenGroupAPI.Endpoint.onion.path).to(equal("oxen/v4/lsrpc"))
                expect(OpenGroupAPI.Endpoint.batch.path).to(equal("batch"))
                expect(OpenGroupAPI.Endpoint.sequence.path).to(equal("sequence"))
                expect(OpenGroupAPI.Endpoint.capabilities.path).to(equal("capabilities"))
                
                // Rooms
                
                expect(OpenGroupAPI.Endpoint.rooms.path).to(equal("rooms"))
                expect(OpenGroupAPI.Endpoint.room("test").path).to(equal("room/test"))
                expect(OpenGroupAPI.Endpoint.roomPollInfo("test", 123).path).to(equal("room/test/pollInfo/123"))
                
                // Messages
                
                expect(OpenGroupAPI.Endpoint.roomMessage("test").path).to(equal("room/test/message"))
                expect(OpenGroupAPI.Endpoint.roomMessageIndividual("test", id: 123).path).to(equal("room/test/message/123"))
                expect(OpenGroupAPI.Endpoint.roomMessagesRecent("test").path).to(equal("room/test/messages/recent"))
                expect(OpenGroupAPI.Endpoint.roomMessagesBefore("test", id: 123).path).to(equal("room/test/messages/before/123"))
                expect(OpenGroupAPI.Endpoint.roomMessagesSince("test", seqNo: 123).path)
                    .to(equal("room/test/messages/since/123"))
                expect(OpenGroupAPI.Endpoint.roomDeleteMessages("test", sessionId: "testId").path)
                    .to(equal("room/test/all/testId"))
                
                // Pinning
                
                expect(OpenGroupAPI.Endpoint.roomPinMessage("test", id: 123).path).to(equal("room/test/pin/123"))
                expect(OpenGroupAPI.Endpoint.roomUnpinMessage("test", id: 123).path).to(equal("room/test/unpin/123"))
                expect(OpenGroupAPI.Endpoint.roomUnpinAll("test").path).to(equal("room/test/unpin/all"))
                
                // Files
                
                expect(OpenGroupAPI.Endpoint.roomFile("test").path).to(equal("room/test/file"))
                expect(OpenGroupAPI.Endpoint.roomFileIndividual("test", "123").path).to(equal("room/test/file/123"))
                
                // Inbox/Outbox (Message Requests)
                
                expect(OpenGroupAPI.Endpoint.inbox.path).to(equal("inbox"))
                expect(OpenGroupAPI.Endpoint.inboxSince(id: 123).path).to(equal("inbox/since/123"))
                expect(OpenGroupAPI.Endpoint.inboxFor(sessionId: "test").path).to(equal("inbox/test"))
                
                expect(OpenGroupAPI.Endpoint.outbox.path).to(equal("outbox"))
                expect(OpenGroupAPI.Endpoint.outboxSince(id: 123).path).to(equal("outbox/since/123"))
                
                // Users
                
                expect(OpenGroupAPI.Endpoint.userBan("test").path).to(equal("user/test/ban"))
                expect(OpenGroupAPI.Endpoint.userUnban("test").path).to(equal("user/test/unban"))
                expect(OpenGroupAPI.Endpoint.userModerator("test").path).to(equal("user/test/moderator"))
            }
        }
    }
}

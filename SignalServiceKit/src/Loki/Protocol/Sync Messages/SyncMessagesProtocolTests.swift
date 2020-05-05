import PromiseKit
@testable import SignalServiceKit
import XCTest

class SyncMessagesProtocolTests : XCTestCase {

    private var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }
    private var messageSender: OWSFakeMessageSender { MockSSKEnvironment.shared.messageSender as! OWSFakeMessageSender }

    override func setUp() {
        super.setUp()
        LokiTestUtilities.setUpMockEnvironment()
    }

    func testContactSyncMessageHandling() {
        // Let's say Alice and Bob have an ongoing conversation. Alice now links a device. Let's call Alice's master device A1
        // and her slave device A2, and let's call Bob's device B. When Alice links A2 to A1, A2 needs to somehow establish a
        // session with B (it already established a session with A1 when the devices were linked). How does it do this?
        //
        // As part of the linking process, A2 should've received a contact sync from A1. Upon receiving this contact sync,
        // A2 should send out AFRs to the subset of the contacts it received from A1 for which it doesn't yet have a session (in
        // theory this should be all of them).
        let base64EncodedContactData = "AAAA7QpCMDU0ZmI2M2IxYTU4YjU1YTcwNjMxODkyOWRjNmQxMWM4ZWY3OTAxMTZhNzRjOWFmNTVmYTZhMzZlNjhmMTYzYTMyEhBZMyAoLi4uOGYxNjNhMzIpIgZvcmFuZ2UqaQpCMDU0ZmI2M2IxYTU4YjU1YTcwNjMxODkyOWRjNmQxMWM4ZWY3OTAxMTZhNzRjOWFmNTVmYTZhMzZlNjhmMTYzYTMyEiEFT7Y7Gli1WnBjGJKdxtEcjveQEWp0ya9V+mo25o8WOjIYADIgXAgtAlrJr81tnuWyk8TgJhdsKzz+yIui5mXnbcMyPk1AAAAAAOwKQjA1Nzg4MmQzM2E4OTI1NDdiOTI2NjIyYjk0ZDZjMWNmYjI1ZmY2YTczZmQ4OTZlMWIxNmY1ODI0NzRjZjQ3MDE2YhIQWTQgKC4uLmNmNDcwMTZiKSIFYnJvd24qaQpCMDU3ODgyZDMzYTg5MjU0N2I5MjY2MjJiOTRkNmMxY2ZiMjVmZjZhNzNmZDg5NmUxYjE2ZjU4MjQ3NGNmNDcwMTZiEiEFeILTOoklR7kmYiuU1sHPsl/2pz/YluGxb1gkdM9HAWsYADIgD1QA1ofVIccRhbx8AnbygQYo5iOiyGUMG/sGNP1ENRJAAAAAAPAKQjA1OTUyYTRiNTFjNDJkZWE2OWEwYWNhNWU2OTgxYTQ2MDk0NGI2Yjc0NjdkOWQ5OTliOWU3NjExNzdkYWI1NzIxMxIQWTEgKC4uLmRhYjU3MjEzKSIJYmx1ZV9ncmV5KmkKQjA1OTUyYTRiNTFjNDJkZWE2OWEwYWNhNWU2OTgxYTQ2MDk0NGI2Yjc0NjdkOWQ5OTliOWU3NjExNzdkYWI1NzIxMxIhBZUqS1HELeppoKyl5pgaRglEtrdGfZ2Zm552EXfatXITGAAyIBkyX0S08IAuov6faUvaxYsfJtdpww1G4LF6bG5vG7L+QAA="
        let contactData = Data(base64Encoded: base64EncodedContactData)!
        let parser = ContactParser(data: contactData)
        let hexEncodedPublicKeys = parser.parseHexEncodedPublicKeys()
        let expectation = self.expectation(description: "Send friend request messages")
        var messageCount = 0
        let messageSender = self.messageSender
        messageSender.sendMessageWasCalledBlock = { sentMessage in
            messageCount += 1
            guard sentMessage is FriendRequestMessage else {
                return XCTFail("Expected a friend request to be sent, but found: \(sentMessage).")
            }
            guard messageCount == hexEncodedPublicKeys.count else { return }
            expectation.fulfill()
            messageSender.sendMessageWasCalledBlock = nil
        }
        storage.dbReadWriteConnection.readWrite { transaction in
            SyncMessagesProtocol.handleContactSyncMessageData(contactData, using: transaction)
        }
        wait(for: [ expectation ], timeout: 1)
        /* TODO: Re-enable when we've split friend request logic from OWSMessageSender
        hexEncodedPublicKeys.forEach { hexEncodedPublicKey in
            var friendRequestStatus: LKFriendRequestStatus!
            storage.dbReadWriteConnection.readWrite { transaction in
                friendRequestStatus = self.storage.getFriendRequestStatus(for: hexEncodedPublicKey, transaction: transaction)
            }
            XCTAssert(friendRequestStatus == .requestSent)
        }
        */
        // TODO: Test the case where Bob has multiple devices
    }
}

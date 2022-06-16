// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionMessagingKit

extension OpenGroup: Mocked {
    static var mockValue: OpenGroup = OpenGroup(
        server: any(),
        roomToken: any(),
        publicKey: TestConstants.publicKey,
        name: any(),
        isActive: any(),
        roomDescription: any(),
        imageId: any(),
        imageData: any(),
        userCount: any(),
        infoUpdates: any(),
        sequenceNumber: any(),
        inboxLatestMessageId: any(),
        outboxLatestMessageId: any()
    )
}

extension VisibleMessage: Mocked {
    static var mockValue: VisibleMessage = VisibleMessage()
}

extension BlindedIdMapping: Mocked {
    static var mockValue: BlindedIdMapping = BlindedIdMapping(
        blindedId: any(),
        sessionId: any(),
        serverPublicKey: any()
    )
}

// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionMessagingKit

extension OpenGroup: Mocked {
    static var mockValue: OpenGroup = OpenGroup(
        server: any(),
        room: any(),
        publicKey: TestConstants.publicKey,
        name: any(),
        groupDescription: any(),
        imageID: any(),
        infoUpdates: any()
    )
}

extension OpenGroupAPI.Server: Mocked {
    static var mockValue: OpenGroupAPI.Server = OpenGroupAPI.Server(
        name: any(),
        capabilities: OpenGroupAPI.Capabilities(capabilities: any(), missing: any())
    )
}

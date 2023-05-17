//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class MockSgxWebsocketConnection: SgxWebsocketConnection {
    public var onSendRequestAndReadResponse: ((Data) -> Promise<Data>)?
    public func sendRequestAndReadResponse(_ request: Data) -> Promise<Data> {
        onSendRequestAndReadResponse!(request)
    }

    public var onSendRequestAndReadAllResponses: ((Data) -> Promise<[Data]>)?
    public func sendRequestAndReadAllResponses(_ request: Data) -> Promise<[Data]> {
        onSendRequestAndReadAllResponses!(request)
    }

    public var onDisconnect: (() -> Void)?
    public func disconnect() {
        onDisconnect?()
    }
}

#endif

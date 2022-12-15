//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension WebSocketFactory {
    func webSocketPromise(request: URLRequest, queue: DispatchQueue) -> WebSocketPromise? {
        guard let webSocket = buildSocket(request: request, callbackQueue: queue) else {
            return nil
        }
        return WebSocketPromise(webSocket: webSocket)
    }
}

/// An object that enables Promise operations on web sockets.
///
/// This object is designed for a request/response paradigm. It's not as
/// useful for full duplex communication where either party may send a
/// message at any time.
///
/// Errors are only surfaced when attempting to read from the socket, and
/// `connect`/`disconnect`/`send(data:)` don't return Promises. Thus, in
/// order to learn out connection failures, send failures, etc., callers
/// must read from the socket.
final class WebSocketPromise: SSKWebSocketDelegate {
    private let webSocket: SSKWebSocket

    /// Initialize a WebSocketPromise & try to connect.
    ///
    /// If an error occurs while connecting, it'll be reported on the first
    /// invocation of  `waitForResponse`/`waitForAllResponses`.
    init(webSocket: SSKWebSocket) {
        self.webSocket = webSocket
        webSocket.delegate = self
        webSocket.connect()
    }

    func disconnect() {
        webSocket.disconnect()
    }

    // MARK: - Sending

    func send(data: Data) {
        webSocket.write(data: data)
    }

    // MARK: - Receiving

    private enum WaitingState {
        case waitingForResponse(Future<Data>)
        case waitingForAllResponses(Future<[Data]>)
    }

    private struct State {
        // A Promise for a caller that's waiting to read a message from the socket.
        var waitingState: WaitingState?

        // If we've received data from the server that needs to be fed into
        // a `waitingState` Promise, it'll be here.
        var receivedMessages = [Data]()

        // If we've received an error or socket closure, it'll be stored here. We
        // consider this after any pending data values to support cases where the
        // final value is immediately followed by a socket closure.
        var socketError: Error?
    }

    private var state = AtomicValue(State(), lock: AtomicLock())

    /// Read one message from the underlying web socket.
    ///
    /// If a connection failure or write error occurred, it will be reported
    /// here in lieu of the next message.
    ///
    /// The caller must ensure that `waitForResponse` and `waitForAllResponses`
    /// are called sequentially. After calling one of these methods, the caller
    /// must wait until the Promise is resolved before calling either method.
    func waitForResponse() -> Promise<Data> {
        let (promise, future) = Promise<Data>.pending()
        updateState { state in
            owsAssert(state.waitingState == nil)
            state.waitingState = .waitingForResponse(future)
        }
        return promise
    }

    /// Read all remaining messages from the underlying web socket.
    ///
    /// If a connection failure or write error occurred, it will be reported
    /// here in lieu of the next message.
    ///
    /// The caller must ensure that `waitForResponse` and `waitForAllResponses`
    /// are called sequentially. After calling one of these methods, the caller
    /// must wait until the Promise is resolved before calling either method.
    ///
    /// - Returns:
    ///     All remaining messages if the web socket is closed with the
    ///     `WebSocketError.normalClosure` code. Otherwise, rejects the promise
    ///     with the error that prevented the socket from closing normally.
    func waitForAllResponses() -> Promise<[Data]> {
        let (promise, future) = Promise<[Data]>.pending()
        updateState { state in
            owsAssert(state.waitingState == nil)
            state.waitingState = .waitingForAllResponses(future)
        }
        return promise
    }

    private func updateState(updateBlock: (inout State) -> Void) {
        var resolveBlock: (() -> Void)?
        state.map { oldState in
            var mutableState = oldState

            // This might be a new message, an error, or a caller requesting the next message.
            updateBlock(&mutableState)

            // Figure out if we have a match -- do we have waiting promise & the next message?
            resolveBlock = resolvePendingResponse(&mutableState)

            // If we resolved the current caller, we get ready for the next caller.
            if resolveBlock != nil {
                mutableState.waitingState = nil
            }

            return mutableState
        }
        // Resolving a Promise may re-entrantly request the next one, so don't hold
        // the lock while running code outside this class.
        resolveBlock?()
    }

    private func resolvePendingResponse(_ state: inout State) -> (() -> Void)? {
        switch state.waitingState {
        case .none:
            return nil
        case .waitingForResponse(let future):
            if !state.receivedMessages.isEmpty {
                let receivedMessage = state.receivedMessages.removeFirst()
                return { future.resolve(receivedMessage) }
            }
            if let socketError = state.socketError {
                return { future.reject(socketError) }
            }
            // Keep waiting until we receive a message or an error.
            return nil
        case .waitingForAllResponses(let future):
            switch state.socketError {
            case .some(WebSocketError.closeError(statusCode: WebSocketError.normalClosure, closeReason: _)):
                let receivedMessages = state.receivedMessages
                state.receivedMessages = []
                return { future.resolve(receivedMessages) }
            case .some(let socketError):
                return { future.reject(socketError) }
            case .none:
                break
            }
            // Keep waiting until the socket is closed.
            return nil
        }
    }

    // MARK: - SSKWebSocketDelegate

    func websocketDidConnect(socket: SSKWebSocket) {
        Logger.info("WebSocket: Socket opened")
    }

    func websocketDidDisconnectOrFail(socket: SSKWebSocket, error: Error) {
        owsAssertDebug(self.webSocket === socket)

        switch error {
        case WebSocketError.closeError(statusCode: WebSocketError.normalClosure, closeReason: _):
            Logger.info("WebSocket: Socket closed normally")
        default:
            Logger.warn("WebSocket: Socket closed with error: \(error)")
        }

        updateState { state in
            guard state.socketError == nil else {
                owsFailDebug("Socket should be closed only once.")
                return
            }
            state.socketError = error
        }
    }

    func websocket(_ socket: SSKWebSocket, didReceiveData data: Data) {
        updateState { state in
            state.receivedMessages.append(data)
        }
    }
}

//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class SocketManager: NSObject {

    private let websocketIdentified = OWSWebSocket(webSocketType: .identified)
    private let websocketUnidentified = OWSWebSocket(webSocketType: .unidentified)

    @objc
    public required override init() {
        AssertIsOnMainThread()

        super.init()

        SwiftSingletons.register(self)
    }

    private func webSocket(ofType webSocketType: OWSWebSocketType) -> OWSWebSocket {
        switch webSocketType {
        case .identified:
            return websocketIdentified
        case .unidentified:
            return websocketUnidentified
        }
    }

    public func canMakeRequests(webSocketType: OWSWebSocketType) -> Bool {
        webSocket(ofType: webSocketType).canMakeRequests
    }

    // TODO: Remove?
    // TODO: Introduce retry?
    public func makeRequest(_ request: TSRequest,
                            webSocketType: OWSWebSocketType,
                            success: @escaping TSSocketMessageSuccess,
                            failure: @escaping TSSocketMessageFailure) {
        webSocket(ofType: webSocketType).makeRequest(request, success: success, failure: failure)
    }

    // TODO: Introduce retry?
    func makeRequestPromise(request: TSRequest, webSocketType: OWSWebSocketType) -> Promise<HTTPResponse> {
        let (promise, resolver) = Promise<HTTPResponse>.pending()
        makeRequest(request,
                    webSocketType: webSocketType,
                    success: { (response: HTTPResponse) in
                        resolver.fulfill(response)
                    },
                    failure: { (failure: OWSHTTPErrorWrapper) in
                        resolver.reject(failure.error)
                    })
        return promise
    }

    // This method can be called from any thread.
    @objc
    public func requestSocketOpen() {
        websocketIdentified.requestOpen()
        websocketUnidentified.requestOpen()
    }

    @objc
    public func cycleSocket() {
        AssertIsOnMainThread()

        websocketIdentified.cycle()
        websocketUnidentified.cycle()
    }

    @objc
    public var isAnySocketOpen: Bool {
        // TODO: Use CaseIterable
        (socketState(forType: .identified) == .open ||
         socketState(forType: .unidentified) == .open)
    }

    public func socketState(forType webSocketType: OWSWebSocketType) -> OWSWebSocketState {
        webSocket(ofType: webSocketType).state
    }

    public var hasEmptiedInitialQueue: Bool {
        websocketIdentified.hasEmptiedInitialQueue
    }
}

//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class SocketManager: NSObject {

    private let websocketDefault = OWSWebSocket(webSocketType: .default)
    private let websocketUD = OWSWebSocket(webSocketType: .UD)

    @objc
    public required override init() {
        AssertIsOnMainThread()

        super.init()

        SwiftSingletons.register(self)
    }

    private func webSocket(ofType webSocketType: OWSWebSocketType) -> OWSWebSocket {
        switch webSocketType {
        case .default:
            return websocketDefault
        case .UD:
            return websocketUD
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
        websocketDefault.requestOpen()
        websocketUD.requestOpen()
    }

    @objc
    public func cycleSocket() {
        AssertIsOnMainThread()

        websocketDefault.cycle()
        websocketUD.cycle()
    }

    @objc
    public var isAnySocketOpen: Bool {
        // TODO: Use CaseIterable
        (socketState(forType: .default) == .open ||
         socketState(forType: .UD) == .open)
    }

    public func socketState(forType webSocketType: OWSWebSocketType) -> OWSWebSocketState {
        webSocket(ofType: webSocketType).state
    }

    public var hasEmptiedInitialQueue: Bool {
        websocketDefault.hasEmptiedInitialQueue
    }
}

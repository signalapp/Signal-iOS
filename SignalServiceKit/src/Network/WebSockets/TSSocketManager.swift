//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension TSSocketManager {
    func makeRequestPromise(request: TSRequest, webSocketType: OWSWebSocketType) -> Promise<Any?> {
        let (promise, resolver) = Promise<Any?>.pending()
        self.make(request,
                  webSocketType: webSocketType,
                  success: { (responseObject: Any?) in
                    resolver.fulfill(responseObject)
        },
                  failure: { (statusCode: Int, responseData: Data?, error: Error) in
                    if IsNetworkConnectivityFailure(error) {
                        Logger.warn("Error: \(error), statusCode: \(statusCode), responseData: \(String(describing: responseData))")
                    } else {
                        owsFailDebug("Error: \(error), statusCode: \(statusCode), responseData: \(String(describing: responseData))")
                    }
                    resolver.reject(error)
        })

        return promise
    }
}

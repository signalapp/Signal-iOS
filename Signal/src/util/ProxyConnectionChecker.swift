//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

enum ProxyConnectionChecker: Dependencies {
    static func checkConnectionAndNotify(completion: @escaping (Bool) -> Void) {
        var observer: NSObjectProtocol?
        func unregisterObserver() {
            observer.map { NotificationCenter.default.removeObserver($0) }
            observer = nil
        }

        var hasTransitionedToConnecting = false

        // Wait to see if we can establish a websocket connection via the new proxy.
        observer = NotificationCenter.default.addObserver(forName: OWSWebSocket.webSocketStateDidChange, object: nil, queue: nil) { _ in
            switch self.socketManager.socketState(forType: .identified) {
            case .closed:
                // Ignore closed state until we start connecting, it's expected that old sockets will close
                guard hasTransitionedToConnecting else { break }

                unregisterObserver()
                completion(false)
            case .connecting:
                hasTransitionedToConnecting = true
            case .open:
                unregisterObserver()
                completion(true)
            }
        }
    }
}

//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

protocol ChatListProxyButtonDelegate: AnyObject {
    func didUpdateButton(_ proxyButtonCreator: ChatListProxyButtonCreator)
    func didTapButton(_ proxyButtonCreator: ChatListProxyButtonCreator)
}

final class ChatListProxyButtonCreator: NSObject {
    private let socketManager: SocketManager
    weak var delegate: ChatListProxyButtonDelegate?

    private var observers = [NSObjectProtocol]()
    private var proxyState: OWSWebSocketState?

    init(socketManager: SocketManager) {
        self.socketManager = socketManager
        super.init()
        // The display of the button depends on `SignalProxy.isEnabled` and the
        // current status of the web socket. In theory, we should refresh the
        // button whenever either changes. However, whenever the proxy is enabled
        // or disabled, we disconnect & reconnect the web socket, so we can rely
        // entirely on those state transitions for this button.
        observers.append(NotificationCenter.default.addObserver(
            forName: OWSWebSocket.webSocketStateDidChange,
            object: nil,
            queue: .main,
            using: { [weak self] _ in self?.updateState() }
        ))
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func updateState() {
        let newValue: OWSWebSocketState? = {
            guard SignalProxy.isEnabled else {
                return nil
            }
            return socketManager.socketState(forType: .identified)
        }()
        let didUpdate = self.proxyState != newValue
        self.proxyState = newValue
        if didUpdate {
            delegate?.didUpdateButton(self)
        }
    }

    func buildButton() -> UIBarButtonItem? {
        guard let proxyState else {
            return nil
        }
        let proxyStatusImage: UIImage?
        let tintColor: UIColor
        switch proxyState {
        case .open:
            proxyStatusImage = UIImage(named: "safety-number")
            tintColor = UIColor.ows_accentGreen
        case .closed:
            proxyStatusImage = UIImage(named: "error-shield")
            tintColor = UIColor.ows_accentRed
        case .connecting:
            proxyStatusImage = UIImage(named: "error-shield")
            tintColor = UIColor.ows_middleGray
        }
        let button = UIBarButtonItem(
            image: proxyStatusImage,
            style: .plain,
            target: self,
            action: #selector(didTapButton)
        )
        button.tintColor = tintColor
        return button
    }

    @objc
    private func didTapButton() { delegate?.didTapButton(self) }
}

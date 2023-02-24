//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Credentials to use on a TSRequest to the chat server.
@objc
public class ChatServiceAuth: NSObject {
    public enum Mode {
        case implicit
        case explicit
    }

    public let aci: UUID?
    public let password: String?

    private init(aci: UUID?, password: String?) {
        self.aci = aci
        self.password = password
        super.init()
    }

    /// Will use auth credentials present on TSAccountManager
    @objc
    public static func implicit() -> ChatServiceAuth {
        return ChatServiceAuth(aci: nil, password: nil)
    }

    @objc
    public static func explicit(aci: UUID, password: String) -> ChatServiceAuth {
        return ChatServiceAuth(aci: aci, password: password)
    }

    @objc
    public var username: String? {
        return aci?.uuidString
    }

    public var mode: Mode { (aci == nil || password == nil) ? .implicit : .explicit }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(aci)
        hasher.combine(password)
        return hasher.finalize()
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ChatServiceAuth else {
            return false
        }
        return aci == other.aci && password == other.password
    }
}

extension TSRequest {
    @objc
    public func setAuth(_ auth: ChatServiceAuth) {
        self.authUsername = auth.username
        self.authPassword = auth.password
    }
}

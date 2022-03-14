//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

/// Wraps the stores for 1:1 sessions that use the Signal Protocol (Double Ratchet + X3DH).
@objc
public class SignalProtocolStore: NSObject {
    @objc
    public let sessionStore: SSKSessionStore = .init()
    @objc
    public let preKeyStore: SSKPreKeyStore = .init()
    @objc
    public let signedPreKeyStore: SSKSignedPreKeyStore = .init()
}

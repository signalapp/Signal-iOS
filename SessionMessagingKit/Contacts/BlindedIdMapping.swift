// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

@objc(SNBlindedIdMapping)
public final class BlindedIdMapping: NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    @objc public let blindedId: String
    @objc public let sessionId: String
    @objc public let serverPublicKey: String
    
    // MARK: - Initialization
    
    @objc public init(blindedId: String, sessionId: String, serverPublicKey: String) {
        self.blindedId = blindedId
        self.sessionId = sessionId
        self.serverPublicKey = serverPublicKey
        
        super.init()
    }

    private override init() { preconditionFailure("Use init(blindedId:sessionId:) instead.") }

    // MARK: - Coding
    
    public required init?(coder: NSCoder) {
        guard let blindedId: String = coder.decodeObject(forKey: "blindedId") as! String? else { return nil }
        guard let sessionId: String = coder.decodeObject(forKey: "sessionId") as! String? else { return nil }
        guard let serverPublicKey: String = coder.decodeObject(forKey: "serverPublicKey") as! String? else { return nil }
        
        self.blindedId = blindedId
        self.sessionId = sessionId
        self.serverPublicKey = serverPublicKey
    }

    public func encode(with coder: NSCoder) {
        coder.encode(blindedId, forKey: "blindedId")
        coder.encode(sessionId, forKey: "sessionId")
        coder.encode(serverPublicKey, forKey: "serverPublicKey")
    }
}

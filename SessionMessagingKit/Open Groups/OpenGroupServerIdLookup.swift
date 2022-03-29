// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

@objc(SNOpenGroupServerIdLookup)
public final class OpenGroupServerIdLookup: NSObject, NSCoding {    // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    @objc public let id: String
    @objc public let serverId: UInt64
    @objc public let tsMessageId: String
    
    // MARK: - Initialization
        
    @objc public init(server: String, room: String, serverId: UInt64, tsMessageId: String) {
        self.id = OpenGroupServerIdLookup.id(serverId: serverId, in: room, on: server)
        self.serverId = serverId
        self.tsMessageId = tsMessageId

        super.init()
    }

    private override init() { preconditionFailure("Use init(blindedId:sessionId:) instead.") }

    // MARK: - Coding
    
    public required init?(coder: NSCoder) {
        guard let id: String = coder.decodeObject(forKey: "id") as! String? else { return nil }
        guard let serverId: UInt64 = coder.decodeObject(forKey: "serverId") as! UInt64? else { return nil }
        guard let tsMessageId: String = coder.decodeObject(forKey: "tsMessageId") as! String? else { return nil }

        self.id = id
        self.serverId = serverId
        self.tsMessageId = tsMessageId
    }

    public func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(serverId, forKey: "serverId")
        coder.encode(tsMessageId, forKey: "tsMessageId")
    }
    
    // MARK: - Convenience
    
    static func id(serverId: UInt64, in room: String, on server: String) -> String {
        return "\(server).\(room).\(serverId)"
    }
}

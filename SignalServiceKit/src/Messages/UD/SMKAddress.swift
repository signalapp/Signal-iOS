//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
// 

import Foundation

public enum SMKAddress {
    case both(uuid: UUID, e164: String)
    case uuid(_ uuid: UUID)
    case e164(_ e164: String)
}

public extension SMKAddress {
    init(uuid: UUID?, e164: String?) throws {
        switch (uuid, e164) {
        case (.some(let uuid), .some(let e164)):
            self = .both(uuid: uuid, e164: e164)
        case (.some(let uuid), .none):
            self = .uuid(uuid)
        case (.none, .some(let e164)):
            self = .e164(e164)
        case (.none, .none):
            throw SMKError.invalidInput("had neither uuid nor e164")
        }
    }

    var uuid: UUID? {
        switch self {
        case .both(let uuid, _):
            return uuid
        case .uuid(let uuid):
            return uuid
        case .e164:
            return nil
        }
    }

    var e164: String? {
        switch self {
        case .both(_, let e164):
            return e164
        case .uuid:
            return nil
        case .e164(let e164):
            return e164
        }
    }

    func matches(_ other: SMKAddress) -> Bool {
        switch self {
        case .both(let uuid, let e164):
            if other.uuid == uuid || other.e164 == e164 {
                // If one matches, then the other should also match
                // if it's available
                assert(other.uuid == uuid || other.uuid == nil)
                assert(other.e164 == e164 || other.e164 == nil)

                return true
            } else {
                return false
            }
        case .uuid(let uuid):
            return other.uuid == uuid
        case .e164(let e164):
            return other.e164 == e164
        }
    }
}

extension SMKAddress: Equatable, Hashable { }

//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMetadataKit
import ZKGroup

public extension UUID {
    func asZKGUuid() throws -> ZKGUuid {
        return try withUnsafeBytes(of: self.uuid) { (buffer: UnsafeRawBufferPointer) in
            try ZKGUuid(contents: [UInt8](buffer))
        }
    }
}

// MARK: -

public extension ZKGUuid {
    func asUUID() -> UUID {
        return serialize().asData.withUnsafeBytes {
            UUID(uuid: $0.bindMemory(to: uuid_t.self).first!)
        }
    }
}

// MARK: -

public extension ProfileKeyVersion {
    // GroupsV2 TODO: We might move this to the wrappers.
    func asHexadecimalString() throws -> String {
        let profileKeyVersionData = serialize().asData
        // A peculiarity of ProfileKeyVersion is that its contents
        // are an ASCII-encoded hexadecimal string of the profile key
        // version, rather than the raw version bytes.
        guard let profileKeyVersionString = String(data: profileKeyVersionData, encoding: .ascii) else {
            throw OWSAssertionError("Invalid profile key version.")
        }
        return profileKeyVersionString
    }
}

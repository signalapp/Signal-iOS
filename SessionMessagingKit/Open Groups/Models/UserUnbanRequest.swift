// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    struct UserUnbanRequest: Codable {
        /// List of one or more room tokens from which the user should be banned (the invoking user must be a `moderator`
        /// of all of the given rooms
        ///
        /// This may be set to the single-element list ["*"] to ban the user from all rooms in which the invoking user has `moderator`
        /// permissions (the call will succeed if the calling user is a moderator in at least one channel)
        ///
        /// Exclusive of `global`
        let rooms: [String]?
        
        /// If true then remove a server-wide global ban
        ///
        /// Exclusive of rooms
        let global: Bool?
    }
}

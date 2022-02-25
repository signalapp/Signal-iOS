// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    struct UserBanRequest: Codable {
        /// List of one or more room tokens from which the user should be banned (the invoking user must be a `moderator`
        /// of all of the given rooms
        ///
        /// This may be set to the single-element list ["*"] to ban the user from all rooms in which the invoking user has `moderator`
        /// permissions (the call will succeed if the calling user is a moderator in at least one channel)
        ///
        /// Exclusive of `global`
        let rooms: [String]?
        
        /// If true then apply the ban at the server-wide global level: the user will be banned from the server entirely—not merely from
        /// all rooms, but also from calling any other server request (the invoking user must be a global `moderator` in order to add
        /// a global ban
        ///
        /// Exclusive of rooms
        let global: Bool?
        
        /// Optional value specifying a time limit on the ban, in seconds
        ///
        /// The applied ban will expire and be removed after the given interval - If omitted (or `null`) then the ban is permanent
        ///
        /// If this endpoint is called multiple times then the timeout of the last call takes effect (eg. a permanent ban can be replaced
        /// with a time-limited ban by calling the endpoint again with a timeout value, and vice versa)
        let timeout: TimeInterval?
    }
}

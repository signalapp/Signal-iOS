// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    struct UserModeratorRequest: Codable {
        /// List of room tokens to which the moderator status should be applied. The invoking user must be an admin of all of the given rooms.
        ///
        /// This may be set to the single-element list ['*'] to add or remove the moderator from all rooms in which the current user has admin
        /// permissions (the call will succeed if the calling user is an admin in at least one channel).
        ///
        /// Exclusive of `global`.  (If you want to apply both at once use two calls, e.g. bundled in a batch request).
        let rooms: [String]?
        
        /// If true then appoint this user as a global moderator or admin of the server. The user will receive moderator/admin ability in all rooms
        /// on the server (both current and future).
        ///
        /// The caller must be a global admin to add/remove a global moderator or admin.
        let global: Bool?
        
        /// If `true` then this user will be granted moderator permission to either the listed room(s) or the server globally.
        ///
        /// If `false` then this user will have their moderator *and admin* permissions removed from the given rooms (or server).  Note
        /// that removing a global moderator only removes the global permission but does not remove individual room moderator permissions
        /// that may also be present.
        ///
        /// See the `admin` parameter description for information on how `admin` and `moderator` parameters interact.
        let moderator: Bool?
        
        /// If `true` then this user will be granted moderator and admin permissions to the given rooms or server.  Admin permissions are
        /// required to appoint new moderators or administrators and to alter room info such as the image, adding/removing pinned messages,
        /// and changing the name/description of the room.
        ///
        /// If false then this user will have their admin permission removed, but will keep moderator permissions.  To remove both moderator and
        /// admin permissions specify `moderator: false` (which implies clearing admin permissions as well).
        ///
        /// Note that removing a global admin only removes the global permission but does not remove individual room admin permissions that
        /// may also be present.
        ///
        /// The `admin`/`moderator` paramters interact as follows:
        /// - `admin=true`, `moderator` omitted: this adds admin permissions, which automatically also implies moderator permissions.
        /// - `admin=true, moderator=true`: exactly the same as above.
        /// - `admin=false, moderator=true`: removes any existing admin permissions from the rooms (or globally), if present, and adds
        /// moderator permissions to the rooms/globally (if not already present).
        /// - `admin=false`, `moderator` omitted: this removes admin permissions but leaves moderator permissions, if present.  (This
        /// effectively "downgrades" an admin to a moderator).  Unlike the above this does *not* add moderator permissions to matching rooms
        /// if not already present.
        /// - `moderator=true`, `admin` omitted: adds moderator permissions to the given rooms (or globally), if not already present.  If
        /// the user already has admin permissions this does nothing (that is, admin permission is *not* removed, unlike the above).
        /// - `moderator=false`, `admin` omitted: this removes moderator *and* admin permissions from all given rooms (or globally).
        /// - `moderator=false, admin=false`: exactly the same as above.
        /// - `moderator=false, admin=true`: this combination is *not* *permitted* (because admin permissions imply moderator
        /// permissions) and will result in Bad Request error if given.
        let admin: Bool?
        
        /// Whether this user should be a "visible" moderator or admin in the specified rooms (or globally).  Visible moderators are identified to all
        /// room users (e.g. via a special status badge in Session clients).
        ///
        /// Invisible moderators/admins have the same permission as as visible ones, but their moderator/admin status is only visible to other
        /// moderators, not to ordinary room participants.
        ///
        /// The default if this field is omitted is true for room-specific moderators/admins and false for server-level global moderators/admins.
        ///
        /// If an admin or moderator has both global and room-specific moderation permissions then the visibility of the admin/mod for that
        /// room's moderator/admin list will use the room-specific visibility value, regardless of the global setting.  (This differs from
        /// moderator/admin permissions themselves, which are additive).
        let visible: Bool
    }
}

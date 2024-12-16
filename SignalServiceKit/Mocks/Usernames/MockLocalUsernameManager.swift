//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

public class MockLocalUsernameManager: LocalUsernameManager {
    var startingUsernameState: Usernames.LocalUsernameState!

    var didSetCorruptedUsername: Bool = false
    var didSetCorruptedLink: Bool = false

    public func usernameState(tx: DBReadTransaction) -> Usernames.LocalUsernameState {
        return startingUsernameState
    }

    public func setLocalUsernameWithCorruptedLink(username: String, tx: DBWriteTransaction) {
        didSetCorruptedLink = true
    }

    public func setLocalUsernameCorrupted(tx: DBWriteTransaction) {
        didSetCorruptedUsername = true
    }

    public func setLocalUsername(username: String, usernameLink: Usernames.UsernameLink, tx: DBWriteTransaction) { owsFail("Not implemented!") }
    public func clearLocalUsername(tx: DBWriteTransaction) { owsFail("Not implemented!") }
    public func usernameLinkQRCodeColor(tx: DBReadTransaction) -> QRCodeColor { owsFail("Not implemented!") }
    public func setUsernameLinkQRCodeColor(color: QRCodeColor, tx: DBWriteTransaction) { owsFail("Not implemented!") }
    public func reserveUsername(usernameCandidates: Usernames.HashedUsername.GeneratedCandidates) -> Guarantee<Usernames.RemoteMutationResult<Usernames.ReservationResult>> { owsFail("Not implemented!") }
    public func confirmUsername(reservedUsername: Usernames.HashedUsername, tx: DBWriteTransaction) -> Guarantee<Usernames.RemoteMutationResult<Usernames.ConfirmationResult>> { owsFail("Not implemented!") }
    public func deleteUsername(tx: DBWriteTransaction) -> Guarantee<Usernames.RemoteMutationResult<Void>> { owsFail("Not implemented!") }
    public func rotateUsernameLink(tx: DBWriteTransaction) -> Guarantee<Usernames.RemoteMutationResult<Usernames.UsernameLink>> { owsFail("Not implemented!") }
    public func updateVisibleCaseOfExistingUsername(newUsername: String, tx: DBWriteTransaction) -> Guarantee<Usernames.RemoteMutationResult<Void>> { owsFail("Not implemented!") }
}

#endif

//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

class TimeElapsedChallenge: SpamChallenge {

    override init(expiry: Date) {
        super.init(expiry: expiry)

        // All this needs to do is wait out the expiration
        state = .deferred(expiry)
    }

    override var state: SpamChallenge.State {
        didSet { state = .deferred(expirationDate) }
    }

    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}

//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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

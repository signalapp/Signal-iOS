//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

class PushChallenge: SpamChallenge {

    private let token: String
    private var failureCount = 0
    private let kMaxFailures = 15

    init(tokenIn: String) {
        token = tokenIn
        super.init(expiry: .distantFuture)
    }

    override public func resolveChallenge() {
        Logger.verbose("Performing push challenge")
        super.resolveChallenge()

        let request = OWSRequestFactory.pushChallengeResponse(withToken: self.token)

        firstly(on: workQueue) {
            self.networkManager.makePromise(request: request)

        }.done(on: workQueue) { _ in
            Logger.verbose("Push challenge completed!")
            self.state = .complete

        }.catch(on: workQueue) { error in
            owsFailDebugUnlessNetworkFailure(error)
            self.failureCount += 1

            if self.failureCount > self.kMaxFailures {
                Logger.info("Too many failures. Making push challenge as complete")
                self.state = .complete

            } else if let statusCode = error.httpStatusCode {
                if (500..<600).contains(statusCode), statusCode != 508 {
                    let retryDate = error.httpRetryAfterDate ?? self.fallbackRetryAfter
                    self.state = .deferred(retryDate)
                } else {
                    Logger.info("Permanent failure. Making push challenge as complete")
                    self.state = .complete
                }

            } else {
                self.state = .deferred(self.fallbackRetryAfter)
            }
        }
    }

    private var fallbackRetryAfter: Date {
        let delay = pow(2, Double(failureCount)) * 0.1
        return Date(timeIntervalSinceNow: delay)
    }

    // MARK: - <Codable>

    enum CodingKeys: String, CodingKey {
        case token, failureCount
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        failureCount = try container.decode(Int.self, forKey: .failureCount)
        try super.init(from: container.superDecoder())
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        try container.encode(failureCount, forKey: .failureCount)
        try super.encode(to: container.superEncoder())
    }

    // MARK: - Dependencies

    var networkManager: TSNetworkManager { SSKEnvironment.shared.networkManager }
}

//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

class CaptchaChallenge: SpamChallenge {

    let token: String
    var captchaToken: String?
    var failureCount = 0
    let kMaxFailures = 15

    init(tokenIn: String, expiry: Date) {
        token = tokenIn
        super.init(expiry: expiry)
    }

    override public func resolveChallenge() {
        Logger.verbose("Performing captcha challenge")
        super.resolveChallenge()

        if captchaToken == nil {
            requestCaptchaFromUser()
        } else {
            notifyServerOfCompletedCaptcha()
        }
    }

    private func requestCaptchaFromUser() {
        // TODO
        workQueue.asyncAfter(deadline: .now() + .seconds(3)) {
            if self.state == .inProgress {
                self.captchaToken = "fake"
                self.state = .actionable
            }
        }
    }

    private func notifyServerOfCompletedCaptcha() {
        guard let captchaToken = captchaToken else {
            owsFailDebug("Expected valid token")
            state = .actionable
            return
        }

        let request = OWSRequestFactory.recaptchChallengeResponse(
            withToken: token,
            captchaToken: captchaToken)

        firstly(on: workQueue) {
            self.networkManager.makePromise(request: request)

        }.done(on: workQueue) { _ in
            Logger.verbose("Captcha challenge completed!")
            self.state = .complete

        }.catch(on: workQueue) { error in
            owsFailDebugUnlessNetworkFailure(error)
            self.failureCount += 1

            if self.failureCount > self.kMaxFailures {
                Logger.info("Too many failures. Deferring action until expiration")
                self.state = .deferred(self.expirationDate)

            } else if let statusCode = error.httpStatusCode {
                // TODO: Replace with a 4xx status code once defined by server
                if String(statusCode) == "4xx" {
                    Logger.info("Server rejected captcha. Clearing and re-notifying user.")
                    self.captchaToken = nil
                    self.state = .actionable

                } else if (500..<600).contains(statusCode), statusCode != 508 {
                    let retryDate = error.httpRetryAfterDate ?? self.fallbackRetryAfter
                    self.state = .deferred(retryDate)

                } else {
                    Logger.info("Permanent failure. Deferring action until expiration")
                    self.state = .deferred(self.expirationDate)
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
        case token, captchaToken, failureCount
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        captchaToken = try container.decode(String?.self, forKey: .captchaToken)
        failureCount = try container.decode(Int.self, forKey: .failureCount)
        try super.init(from: container.superDecoder())
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        try container.encode(captchaToken, forKey: .captchaToken)
        try container.encode(failureCount, forKey: .failureCount)
        try super.encode(to: container.superEncoder())
    }

    // MARK: - Dependencies

    var networkManager: TSNetworkManager { SSKEnvironment.shared.networkManager }
}

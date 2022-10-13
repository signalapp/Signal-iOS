//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

class CaptchaChallenge: SpamChallenge, Dependencies {
    let token: String
    var captchaToken: String? {
        didSet {
            guard oldValue != captchaToken else { return }
            owsAssertDebug(oldValue == nil)
            Logger.info("")
            state = .actionable
        }
    }

    var failureCount: UInt = 0
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
        NotificationCenter.default.postNotificationNameAsync(
            SpamChallengeResolver.NeedsCaptchaNotification, object: nil)
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
                if (500..<600).contains(statusCode), statusCode != 508 {
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
        let interval = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount)
        return Date(timeIntervalSinceNow: interval)
    }

    // MARK: - <Codable>

    enum CodingKeys: String, CodingKey {
        case token, captchaToken, failureCount
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedToken = try container.decodeIfPresent(String.self, forKey: .token)
        let decodedCaptchaToken = try container.decodeIfPresent(String.self, forKey: .captchaToken)
        let decodedFailureCount = try container.decodeIfPresent(UInt.self, forKey: .failureCount)

        token = decodedToken ?? "invalid"
        captchaToken = decodedCaptchaToken
        failureCount = decodedFailureCount ?? 0
        try super.init(from: container.superDecoder())

        if decodedToken == nil {
            owsFailDebug("Invalid decoding")
            state = .failed
        }
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        try container.encode(captchaToken, forKey: .captchaToken)
        try container.encode(failureCount, forKey: .failureCount)
        try super.encode(to: container.superEncoder())
    }
}

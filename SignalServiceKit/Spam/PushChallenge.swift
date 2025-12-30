//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

class PushChallenge: SpamChallenge {

    private var failureCount: UInt = 0
    private let kMaxFailures = 15

    override var pausesMessages: Bool { false }

    init(tokenIn: String? = nil, expiry: Date = .distantFuture) {
        token = tokenIn
        super.init(expiry: expiry)

        if Platform.isSimulator {
            state = .failed
        }
    }

    var token: String? {
        didSet {
            if oldValue == nil {
                state = .actionable
            } else {
                owsFailDebug("Token should only be set non-nil after init.")
            }
        }
    }

    override func resolveChallenge() {
        super.resolveChallenge()

        if let token {
            postToken(token)
        } else {
            requestToken()
        }
    }

    private func requestToken() {
        let request = OWSRequestFactory.pushChallengeRequest()

        Task {
            let result = await Result(catching: {
                try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)
            })
            self.workQueue.async {
                self.handleRequestTokenResult(result)
            }
        }
    }

    private func handleRequestTokenResult(_ result: Result<HTTPResponse, any Error>) {
        assertOnQueue(self.workQueue)
        do {
            _ = try result.get()
            self.state = .deferred(self.expirationDate)

        } catch {
            owsFailDebugUnlessNetworkFailure(error)
            self.failureCount += 1

            if self.failureCount > self.kMaxFailures {
                Logger.info("Too many failures. Making push challenge as failed")
                self.state = .failed

            } else if let statusCode = error.httpStatusCode {
                if (500..<600).contains(statusCode), statusCode != 508 {
                    let retryDate = error.httpRetryAfterDate ?? self.fallbackRetryAfter
                    self.state = .deferred(retryDate)
                } else {
                    Logger.info("Permanent failure. Making push challenge as failed")
                    self.state = .failed
                }

            } else {
                self.state = .deferred(self.fallbackRetryAfter)
            }
        }

    }

    private func postToken(_ token: String) {
        let request = OWSRequestFactory.pushChallengeResponse(token: token)
        Task {
            let result = await Result(catching: {
                try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)
            })
            self.workQueue.async {
                self.handlePostTokenResult(result)
            }
        }
    }

    private func handlePostTokenResult(_ result: Result<HTTPResponse, any Error>) {
        assertOnQueue(self.workQueue)
        do {
            _ = try result.get()
            self.state = .complete

        } catch {
            owsFailDebugUnlessNetworkFailure(error)
            self.failureCount += 1

            if self.failureCount > self.kMaxFailures {
                Logger.info("Too many failures. Making push challenge as complete")
                self.state = .failed

            } else if let statusCode = error.httpStatusCode {
                if (500..<600).contains(statusCode), statusCode != 508 {
                    let retryDate = error.httpRetryAfterDate ?? self.fallbackRetryAfter
                    self.state = .deferred(retryDate)
                } else {
                    Logger.info("Permanent failure. Making push challenge as complete")
                    self.state = .failed
                }

            } else {
                self.state = .deferred(self.fallbackRetryAfter)
            }
        }
    }

    private var fallbackRetryAfter: Date {
        let interval = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount, maxAverageBackoff: 14.1 * .minute)
        return Date(timeIntervalSinceNow: interval)
    }

    // MARK: - <Codable>

    enum CodingKeys: String, CodingKey {
        case token
        case failureCount
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedToken = try container.decodeIfPresent(String.self, forKey: .token)
        let decodedFailureCount = try container.decodeIfPresent(UInt.self, forKey: .token)

        token = decodedToken ?? "invalid"
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
        try container.encode(failureCount, forKey: .failureCount)
        try super.encode(to: container.superEncoder())
    }
}

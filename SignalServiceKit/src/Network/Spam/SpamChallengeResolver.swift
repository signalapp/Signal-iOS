//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSSpamChallengeResolver)
public class SpamChallengeResolver: NSObject, SpamChallengeSchedulingDelegate {

    // Post-initial load, all work should be done on this queue
    var workQueue: DispatchQueue { Self.workQueue }
    private static let workQueue = DispatchQueue(
        label: "org.signal.SpamChallengeResolver",
        target: .sharedUtility)

    private var challenges: [SpamChallenge]?
    private var nextAttemptTimer: Timer? {
        didSet { oldValue?.invalidate() }
    }

    @objc override init() {
        super.init()
        SwiftSingletons.register(self)

        guard FeatureFlags.spamChallenges else { return }
        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.loadChallengesFromDatabase()
            Logger.info("Loaded \(self.challenges?.count ?? -1) unresolved challenges")
        }
    }

    // MARK: - Public

    @objc
    public func didReceiveIncomingPushChallenge(token: String) {
        guard AppReadiness.isAppReady else {
            owsFailDebug("App not ready")
            return
        }
        guard FeatureFlags.spamChallenges else { return }

        workQueue.async {
            let challenge = PushChallenge(tokenIn: token)
            challenge.schedulingDelegate = self
            self.challenges?.append(challenge)
            self.recheckChallenges()
        }
    }

    @objc
    public func serverFlaggedRequestAsPotentialSpam(responseBody: Data) {
        guard AppReadiness.isAppReady else {
            owsFailDebug("App not ready")
            return
        }
        guard FeatureFlags.spamChallenges else { return }

        guard let rawJSON = try? JSONSerialization.jsonObject(with: responseBody, options: []),
              let json = rawJSON as? [String: Any],
              let requirement = json["required"] as? String,
              let token = json["token"] as? String,
              let options = json["options"] as? [String],
              let retryAfterTimestamp = json["retry-after"] as? UInt64 else {
            owsFailDebug("Invalid server spam request response body: \(responseBody)")
            return
        }

        guard requirement == "human" else {
            owsFailDebug("Unrecognized server challenge request")
            return
        }

        let expiry = Date(millisecondsSince1970: retryAfterTimestamp)
        let challenge: SpamChallenge
        if options.contains("recaptcha") {
            challenge = CaptchaChallenge(tokenIn: token, expiry: expiry)
        } else {
            challenge = TimeElapsedChallenge(expiry: expiry)
        }
        challenge.schedulingDelegate = self

        workQueue.async {
            self.challenges?.append(challenge)
            self.recheckChallenges()
        }
    }

    func spamChallenge(_ challenge: SpamChallenge,
                       stateDidChangeFrom priorState: SpamChallenge.State) {
        if challenge.state != .inProgress, challenge.state != priorState {
            workQueue.async { self.recheckChallenges() }
        }
    }

    // MARK: - Private

    private func recheckChallenges() {
        assertOnQueue(workQueue)

        consolidateChallenges()
        saveChallenges()
        scheduleNextUpdate()
        resolveChallenges()
    }

    // Perform any clean up work to consolidate any challenges
    private func consolidateChallenges() {
        assertOnQueue(workQueue)

        let countBefore = challenges?.count ?? 0

        challenges = challenges?
            .filter { $0.state != .complete }
            .filter { $0.expirationDate.isAfterNow }

        if let countAfter = challenges?.count, countBefore != countAfter {
            Logger.info("Removed \(countBefore - countAfter) complete, failed, or expired challenges")
        }
    }

    private func scheduleNextUpdate() {
        assertOnQueue(workQueue)

        let deferral = challenges?
            .compactMap { $0.state.deferralDate }
            .min()

        guard let deferral = deferral else { return }
        guard deferral.isAfterNow else { return }
        guard deferral != nextAttemptTimer?.fireDate else { return }

        Logger.verbose("Deferred challenges will be re-checked at \(deferral)")
        nextAttemptTimer = Timer.scheduledTimer(
            withTimeInterval: deferral.timeIntervalSinceNow,
            repeats: false) { [weak self] _ in

            Logger.verbose("Deferral timer fired!")
            guard let self = self else { return }

            self.workQueue.async {
                self.nextAttemptTimer = nil
                self.recheckChallenges()
            }
        }
    }

    private func resolveChallenges() {
        assertOnQueue(workQueue)

        challenges?.forEach { challenge in
            if challenge.state.isActionable {
                challenge.resolveChallenge()
            }
        }
    }

    // MARK: - Storage

    private let outstandingChallengesKey = "OutstandingChallengesArray"
    private let keyValueStore = SDSKeyValueStore(collection: "SpamChallengeResolver")

    private func loadChallengesFromDatabase() {
        guard challenges == nil else {
            owsFailDebug("")
            return
        }

        do {
            challenges = try SDSDatabaseStorage.shared.read { readTx in
                try keyValueStore.getCodableValue(
                    forKey: outstandingChallengesKey,
                    transaction: readTx)
            } ?? []
        } catch {
            owsFailDebug("Failed to fetch saved challenges")
            challenges = []
        }

        workQueue.async { self.recheckChallenges() }
    }

    private func saveChallenges() {
        assertOnQueue(workQueue)

        do {
            try SDSDatabaseStorage.shared.write { writeTx in
                try keyValueStore.setCodable(
                    challenges,
                    key: outstandingChallengesKey,
                    transaction: writeTx)
            }
        } catch {
            owsFailDebug("Failed to save outstanding challenges")
        }
    }
}


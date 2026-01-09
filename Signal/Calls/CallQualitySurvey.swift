//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit

enum CallQualitySurvey {
    enum CallType: String {
        case individualAudio = "direct_voice"
        case individualVideo = "direct_video"
        case group = "group"
        case link = "call_link"
    }

    enum Rating {
        case satisfied
        case hadIssues(Set<Issue>, customIssue: String?)
    }

    enum Issue: String {
        case audio = "audio"
        case audioStuttering = "audio_stuttering"
        case audioLocalEcho = "audio_local_echo"
        case audioRemoteEcho = "audio_remote_echo"
        case audioDrop = "audio_drop"
        case video = "video"
        case videoNoCamera = "video_no_camera"
        case videoLowQuality = "video_low_quality"
        case videoLowResolution = "video_low_resolution"
        case callDropped = "call_dropped"
        case other = "other"
    }
}

class CallQualitySurveyManager {
    private typealias Proto = CallQualitySurveyProtos_SubmitCallQualitySurveyRequest

    private enum StoreKeys {
        static let lastFailureSubmittedDate = "lastFailureSubmittedDate"
        static let lastPromptDate = "lastPromptDate"
    }

    private let kvStore = NewKeyValueStore(collection: "CallQualitySurveyStore")
    private let logger = PrefixedLogger(prefix: "[CallQualitySurvey]")

    struct Deps {
        let db: DB
        let accountManager: TSAccountManager
        let networkManager: NetworkManager
    }

    private let deps: Deps

    private let callSummary: CallSummary
    private let callType: CallQualitySurvey.CallType

    init(
        callSummary: CallSummary,
        callType: CallQualitySurvey.CallType,
        deps: Deps,
    ) {
        self.callSummary = callSummary
        self.callType = callType
        self.deps = deps
    }

    func showIfNeeded() {
        guard deps.db.read(block: shouldShowSurvey(tx:)) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            UIApplication.shared.frontmostViewController?.present(
                CallQualitySurveyNavigationController(callQualitySurveyManager: self),
                animated: true,
            )

            self.deps.db.write { tx in
                self.kvStore.writeValue(
                    Date(),
                    forKey: StoreKeys.lastPromptDate,
                    tx: tx,
                )
            }
        }
    }

    private func shouldShowSurvey(tx: DBReadTransaction) -> Bool {
        if InMemorySettings.forceCallQualitySurvey {
            return true
        }

        guard callSummary.isSurveyCandidate else { return false }

        let minimumTimeInterval: TimeInterval = .day

        if callSummary.isFailure {
            if
                let lastFailureSubmittedDate = kvStore.fetchValue(
                    Date.self,
                    forKey: StoreKeys.lastFailureSubmittedDate,
                    tx: tx,
                ),
                lastFailureSubmittedDate.addingTimeInterval(minimumTimeInterval).isAfterNow
            {
                // Last failure was submitted within the past 24 hours
                return false
            }

            // No failures have been submitted within the past 24 hours
            return true
        }

        if
            let lastPromptDate = kvStore.fetchValue(
                Date.self,
                forKey: StoreKeys.lastPromptDate,
                tx: tx,
            ),
            lastPromptDate.addingTimeInterval(minimumTimeInterval).isAfterNow
        {
            // Prompt was shown within the past 24 hours
            return false
        }

        let startDate = Date(millisecondsSince1970: callSummary.startTime)
        let endDate = Date(millisecondsSince1970: callSummary.endTime)
        let callWasShort = startDate.addingTimeInterval(.minute) > endDate
        let callWasLong = startDate.addingTimeInterval(25 * .minute) < endDate
        let callLengthWasOutsideNormalRange = callWasShort || callWasLong

        guard let localIdentifiers = deps.accountManager.localIdentifiers(tx: tx) else {
            owsFailBeta("No local identifiers", logger: logger)
            return callLengthWasOutsideNormalRange
        }

        let odds = RemoteConfig.current.callQualitySurveyPPM(localIdentifiers: localIdentifiers)
        let passedRNGCheck = UInt32.random(in: 0..<1_000_000) < odds

        return callLengthWasOutsideNormalRange || passedRNGCheck
    }

    func submit(rating: CallQualitySurvey.Rating, shouldSubmitDebugLogs: Bool) {
        var proto = Proto()
        proto.callType = callType.rawValue
        setCallSummary(proto: &proto, summary: callSummary)
        setRating(proto: &proto, rating: rating)

        Task {
            if shouldSubmitDebugLogs {
                do {
                    let debugLogURL = try await DebugLogs.uploadLogs(dumper: .fromGlobals())
                    proto.debugLogURL = debugLogURL.absoluteString
                } catch {
                    logger.error("Failed to submit debug logs: \(error)")
                }
            }

            do {
                let data = try proto.serializedData()
                let request = createRequest(data: data)
                let response = try await deps.networkManager.asyncRequest(
                    request,
                    retryPolicy: .hopefullyRecoverable,
                )
                if response.responseStatusCode != 204 {
                    throw response.asError()
                }
                logger.info("Call quality survey submitted")
            } catch {
                logger.error("Failed to submit call quality survey: \(error)")
            }

            if callSummary.isFailure {
                deps.db.write { tx in
                    kvStore.writeValue(
                        Date(),
                        forKey: StoreKeys.lastFailureSubmittedDate,
                        tx: tx,
                    )
                }
            }
        }
    }

    private func setRating(proto: inout Proto, rating: CallQualitySurvey.Rating) {
        switch rating {
        case .satisfied:
            proto.userSatisfied = true
            proto.callQualityIssues = []
        case let .hadIssues(issues, customIssue):
            proto.userSatisfied = false
            proto.callQualityIssues = issues.map(\.rawValue)
            if let customIssue {
                proto.additionalIssuesDescription = customIssue
            }
        }
    }

    private func setCallSummary(proto: inout Proto, summary: CallSummary) {
        proto.startTimestamp = Int64(summary.startTime)
        proto.endTimestamp = Int64(summary.endTime)
        proto.callEndReason = summary.callEndReasonText
        proto.success = !summary.isFailure

        if let value = summary.qualityStats.rttMedianConnectionMillis {
            proto.connectionRttMedian = value
        }
        if let value = summary.qualityStats.audioStats.rttMedianMillis {
            proto.audioRttMedian = value
        }
        if let value = summary.qualityStats.videoStats.rttMedianMillis {
            proto.videoRttMedian = value
        }
        if let value = summary.qualityStats.audioStats.jitterMedianReceiveMillis {
            proto.audioRecvJitterMedian = value
        }
        if let value = summary.qualityStats.videoStats.jitterMedianReceiveMillis {
            proto.videoRecvJitterMedian = value
        }
        if let value = summary.qualityStats.audioStats.jitterMedianSendMillis {
            proto.audioSendJitterMedian = value
        }
        if let value = summary.qualityStats.videoStats.jitterMedianSendMillis {
            proto.videoSendJitterMedian = value
        }
        if let value = summary.qualityStats.audioStats.packetLossFractionReceive {
            proto.audioRecvPacketLossFraction = value
        }
        if let value = summary.qualityStats.videoStats.packetLossFractionReceive {
            proto.videoRecvPacketLossFraction = value
        }
        if let value = summary.qualityStats.audioStats.packetLossFractionSend {
            proto.audioSendPacketLossFraction = value
        }
        if let value = summary.qualityStats.videoStats.packetLossFractionSend {
            proto.videoSendPacketLossFraction = value
        }
        if let value = summary.rawStats {
            proto.callTelemetry = value
        }
    }

    private func createRequest(data: Data) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/call_quality_survey")!,
            method: "PUT",
            body: .data(data),
            logger: logger,
        )
        request.auth = .anonymous
        return request
    }
}

private extension CallSummary {
    var isFailure: Bool {
        [
            "internalFailure",
            "signalingFailure",
            "connectionFailure",
            "iceFailedAfterConnected",
        ].contains(callEndReasonText)
    }
}

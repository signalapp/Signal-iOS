//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {

    /// Used to measure and log backup import/export clock time per frame type.
    /// Per-frame metrics exclude time spent in backup file I/O and proto serialization;
    /// this measures time spent reading/writing to our DB and doing CPU processing.
    class Bencher {

        private let dateProvider: DateProviderMonotonic
        private let dbFileSizeBencher: DBFileSizeBencher?

        private let startDate: MonotonicDate

        private var totalFramesProcessed: UInt64 = 0
        private var metrics = [FrameType: Metrics]()
        private var postFrameMetrics = [PostFrameRestoreAction: Metrics]()

        init(
            dateProviderMonotonic: @escaping DateProviderMonotonic,
            dbFileSizeProvider: DBFileSizeProvider
        ) {
            self.dateProvider = dateProviderMonotonic
            self.dbFileSizeBencher = if FeatureFlags.verboseBackupBenchLogging {
                DBFileSizeBencher(dateProvider: dateProviderMonotonic, dbFileSizeProvider: dbFileSizeProvider)
            } else {
                nil
            }

            startDate = dateProviderMonotonic()
        }

        /// Measures the clock time spent in the provided block.
        ///
        /// The provided block takes a ``FrameBencher`` which can itself be provided the
        /// ``BackupProto_Frame``; this is done so the return type doesn't have to be a frame.
        func processFrame<T>(_ block: (FrameBencher) throws -> T) rethrows -> T {
            defer {
                dbFileSizeBencher?.logDBFileSizeIfNecessary(totalFramesProcessed: totalFramesProcessed)
            }

            let frameBencher = FrameBencher(
                bencher: self,
                beforeEnumerationStartDate: nil,
                startDate: dateProvider()
            )
            return try block(frameBencher)
        }

        /// Measures the clock time spent in the provided block.
        func benchPostFrameAction(_ action: PostFrameRestoreAction, _ block: () throws -> Void) rethrows -> Void {
            let startDate = dateProvider()
            try block()
            let durationMs = dateProvider().millisSince(startDate)
            var metrics = postFrameMetrics[action] ?? Metrics()
            metrics.frameCount += 1
            metrics.totalDurationMs += durationMs
            metrics.maxDurationMs = max(durationMs, metrics.maxDurationMs)
            postFrameMetrics[action] = metrics
        }

        /// Given a block that does an enumeration over db objects, wraps that enumeration to instead take
        /// a closure with a FrameBencher that also measures the time spent enumerating.
        func wrapEnumeration<Input, T, Output>(
            _ enumerationFunc: (_ input: Input, (T) throws -> Output) throws -> Void,
            _ input: Input,
            block: @escaping (T, FrameBencher) throws -> Output
        ) rethrows {
            var beforeEnumerationStartDate = dateProvider()
            try enumerationFunc(input) { t in
                let frameBencher = FrameBencher(
                    bencher: self,
                    beforeEnumerationStartDate: beforeEnumerationStartDate,
                    startDate: self.dateProvider()
                )
                let output = try block(t, frameBencher)
                beforeEnumerationStartDate = self.dateProvider()
                return output
            }
        }

        /// Variant of the above where the block doesn't throw; unfortunately `rethrows`
        /// can't cover two layers of throws variations.
        func wrapEnumeration<Input, T, Output>(
            _ enumerationFunc: (_ input: Input, (T) -> Output) throws -> Void,
            _ input: Input,
            block: @escaping (T, FrameBencher) -> Output
        ) rethrows {
            var beforeEnumerationStartDate = dateProvider()
            try enumerationFunc(input) { t in
                let frameBencher = FrameBencher(
                    bencher: self,
                    beforeEnumerationStartDate: beforeEnumerationStartDate,
                    startDate: self.dateProvider()
                )
                let output = block(t, frameBencher)
                beforeEnumerationStartDate = self.dateProvider()
                return output
            }
        }

        class DBFileSizeBencher {
            private let dateProvider: DateProviderMonotonic
            private let dbFileSizeProvider: DBFileSizeProvider

            /// The last time we logged the sizes of database files.
            private var lastDBFileSizeLogDate: MonotonicDate?

            init(
                dateProvider: @escaping DateProviderMonotonic,
                dbFileSizeProvider: DBFileSizeProvider
            ) {
                self.dateProvider = dateProvider
                self.dbFileSizeProvider = dbFileSizeProvider
            }

            func logDBFileSizeIfNecessary(totalFramesProcessed: UInt64) {
                if
                    let lastDBFileSizeLogDate,
                    dateProvider().millisSince(lastDBFileSizeLogDate) < 15 * MSEC_PER_SEC
                {
                    // Bail if we logged recently.
                    return
                }

                let dbFileSize = dbFileSizeProvider.getDatabaseFileSize()
                let walFileSize = dbFileSizeProvider.getDatabaseWALFileSize()
                Logger.info("DB file size: \(dbFileSize), WAL file size: \(walFileSize), frames processed: \(totalFramesProcessed)")

                lastDBFileSizeLogDate = dateProvider()
            }
        }

        /// For measuring processing (import or export) of a single frame.
        class FrameBencher {
            // A bit confusing but if present, this measures the time spent by the
            // enumeration itself (reading the db, deserializing records)
            // versus startDate below is the time spent in the enumeration block.
            private let beforeEnumerationStartDate: MonotonicDate?
            private let startDate: MonotonicDate
            private let bencher: Bencher

            fileprivate init(bencher: Bencher, beforeEnumerationStartDate: MonotonicDate?, startDate: MonotonicDate) {
                self.bencher = bencher
                self.beforeEnumerationStartDate = beforeEnumerationStartDate
                self.startDate = startDate
            }

            func didProcessFrame(_ frame: BackupProto_Frame) {
                guard let frameType = FrameType(frame: frame) else {
                    return
                }

                let durationMs = bencher.dateProvider().millisSince(startDate)
                bencher.totalFramesProcessed += 1

                var metrics = bencher.metrics[frameType] ?? Metrics()
                metrics.frameCount += 1
                metrics.totalDurationMs += durationMs
                metrics.maxDurationMs = max(durationMs, metrics.maxDurationMs)

                if durationMs > Metrics.durationWarningThresholdMs {
                    metrics.frameCountAboveDurationWarningThreshold += 1

                    if FeatureFlags.verboseBackupBenchLogging {
                        metrics.universalFrameCountWhenAboveWarningThreshold.append(bencher.totalFramesProcessed)
                    }
                }

                if FeatureFlags.verboseBackupBenchLogging {
                    metrics.allFrameDurationsMs.append(durationMs)
                }

                if let beforeEnumerationStartDate {
                    metrics.totalEnumerationDurationMs += startDate.millisSince(beforeEnumerationStartDate)
                }

                bencher.metrics[frameType] = metrics
            }
        }

        func logResults() {
            let totalFrameCount = metrics.reduce(0, { $0 + $1.value.frameCount })
            Logger.info("Processed \(loggableCountString(totalFrameCount)) frames in \(dateProvider().millisSince(startDate))ms")

            func logMetrics(_ metrics: Metrics, typeString: String) {
                guard metrics.frameCount > 0 else { return }
                var logString = "\(loggableCountString(metrics.frameCount)) \(typeString)(s) in \(metrics.totalDurationMs)ms."
                if metrics.frameCount > 1 {
                    if FeatureFlags.verboseBackupBenchLogging {
                        let avgMs = metrics.totalDurationMs / metrics.frameCount
                        logString += " Avg:\(avgMs)ms"
                    }
                    logString += " Max:\(metrics.maxDurationMs)ms"
                }
                if metrics.totalEnumerationDurationMs > 0 {
                    logString += " Enum:\(metrics.totalEnumerationDurationMs)ms"
                }
                if metrics.frameCountAboveDurationWarningThreshold > 0 {
                    logString += " AboveThreshold:\(metrics.frameCountAboveDurationWarningThreshold)"
                }
                if metrics.allFrameDurationsMs.count > 0 {
                    let percentileStrings = Percentile.computePercentiles(values: metrics.allFrameDurationsMs)
                        .map { (percentile, duration) in "p\(percentile.rawValue):\(duration)ms" }

                    logString += " FrameDurations:{\(percentileStrings.joined(separator: ","))}"
                }
                if metrics.universalFrameCountWhenAboveWarningThreshold.count > 0 {
                    let percentileStrings = Percentile.computePercentiles(values: metrics.universalFrameCountWhenAboveWarningThreshold)
                        .map { (percentile, totalFrameCount) in "p\(percentile.rawValue):\(totalFrameCount)" }

                    logString += " UnivFrameCountWhenAboveThreshold:{\(percentileStrings.joined(separator: ","))}"
                }
                Logger.info(logString)
            }

            for (frameType, metrics) in self.metrics.sorted(by: { $0.value.totalDurationMs > $1.value.totalDurationMs }) {
                logMetrics(metrics, typeString: frameType.rawValue)
            }
            for (action, metrics) in self.postFrameMetrics.sorted(by: { $0.value.totalDurationMs > $1.value.totalDurationMs }) {
                logMetrics(metrics, typeString: action.rawValue)
            }
        }

        private func loggableCountString(_ number: UInt64) -> String {
            if FeatureFlags.verboseBackupBenchLogging {
                return "\(number)"
            }

            // Only log the order of magnitude
            var magnitude: UInt64 = 1
            while magnitude <= number {
                magnitude *= 10
            }
            let nearestOrderOfMagnitude = magnitude / 10
            return "~\(nearestOrderOfMagnitude)"
        }

        private struct Metrics {
            static let durationWarningThresholdMs: UInt64 = 30

            var frameCount: UInt64 = 0
            var frameCountAboveDurationWarningThreshold: UInt64 = 0
            var totalDurationMs: UInt64 = 0
            var maxDurationMs: UInt64 = 0
            var totalEnumerationDurationMs: UInt64 = 0

            /// - Important
            /// Only set if verbose bench logging is enabled!
            var allFrameDurationsMs: [UInt64] = []

            /// The total frame count, across all frame types, when we processed
            /// a frame for this metric that was above the duration-warning
            /// threshold.
            /// - Important
            /// Only set if verbose bench logging is enabled!
            var universalFrameCountWhenAboveWarningThreshold: [UInt64] = []
        }

        private enum Percentile: Int, CaseIterable {
            case p25 = 25
            case p50 = 50
            case p75 = 75
            case p90 = 90
            case p95 = 95
            case p99 = 99

            static func computePercentiles<T: Comparable>(
                values: [T],
                percentiles: [Percentile] = Percentile.allCases
            ) -> [(Percentile, T)] {
                var percentileValues = [(Percentile, T)]()
                let sortedValues = values.sorted()

                for percentile in percentiles {
                    let index = Int(Double(sortedValues.count) * Double(percentile.rawValue) / 100)
                    let clampedIndex = min(sortedValues.count - 1, index)

                    percentileValues.append((percentile, sortedValues[clampedIndex]))
                }

                return percentileValues
            }
        }

        private enum FrameType: String, CaseIterable {
            case AccountData

            case Recipient_Contact
            case Recipient_Group
            case Recipient_DistributionList
            case Recipient_Self
            case Recipient_CallLink

            case Chat

            case ChatItem_StandardMessage
            case ChatItem_StandardMessage_OversizeText
            case ChatItem_StandardMessage_WithAttachments
            case ChatItem_StandardMessage_Quote
            case ChatItem_StandardMessage_LinkPreview

            case ChatItem_ContactMessage
            case ChatItem_StickerMessage
            case ChatItem_RemoteDeletedMessage

            case ChatItem_ChatUpdateMessage
            case ChatItem_ChatUpdateMessage_SimpleUpdate
            case ChatItem_ChatUpdateMessage_GroupChange
            case ChatItem_ChatUpdateMessage_ExpirationTimerChange
            case ChatItem_ChatUpdateMessage_ProfileChange
            case ChatItem_ChatUpdateMessage_ThreadMerge
            case ChatItem_ChatUpdateMessage_SessionSwitchover
            case ChatItem_ChatUpdateMessage_LearnedProfileChange
            case ChatItem_ChatUpdateMessage_IndividualCall
            case ChatItem_ChatUpdateMessage_GroupCall

            case ChatItem_PaymentNotification
            case ChatItem_GiftBadge
            case ChatItem_ViewOnceMessage
            case ChatItem_DirectStoryReplyMessage

            case StickerPack

            case AdHocCall

            init?(frame: BackupProto_Frame) {
                switch frame.item {
                case .account:
                    self = .AccountData
                case .chat:
                    self = .Chat
                case .stickerPack:
                    self = .StickerPack
                case .adHocCall:
                    self = .AdHocCall
                case .notificationProfile, .chatFolder, .none:
                    // We don't restore and therefore don't benchmark these.
                    return nil

                case .recipient(let recipient):
                    switch recipient.destination {
                    case .contact:
                        self = .Recipient_Contact
                    case .group:
                        self = .Recipient_Group
                    case .distributionList:
                        self = .Recipient_DistributionList
                    case .self_p:
                        self = .Recipient_Self
                    case .callLink:
                        self = .Recipient_CallLink
                    case .releaseNotes, .none:
                        // We don't restore and therefore don't benchmark these.
                        return nil
                    }

                case .chatItem(let chatItem):
                    switch chatItem.item {
                    case .contactMessage:
                        self = .ChatItem_ContactMessage
                    case .stickerMessage:
                        self = .ChatItem_StickerMessage
                    case .remoteDeletedMessage:
                        self = .ChatItem_RemoteDeletedMessage
                    case .paymentNotification:
                        self = .ChatItem_PaymentNotification
                    case .giftBadge:
                        self = .ChatItem_GiftBadge
                    case .viewOnceMessage:
                        self = .ChatItem_ViewOnceMessage
                    case .directStoryReplyMessage:
                        self = .ChatItem_DirectStoryReplyMessage
                    case .none:
                        // We don't restore and therefore don't benchmark these.
                        return nil

                    case .standardMessage(let standardMessage):
                        if standardMessage.hasQuote {
                            self = .ChatItem_StandardMessage_Quote
                        } else if standardMessage.hasLongText {
                            self = .ChatItem_StandardMessage_OversizeText
                        } else if standardMessage.linkPreview.isEmpty.negated {
                            self = .ChatItem_StandardMessage_LinkPreview
                        } else if standardMessage.attachments.isEmpty.negated {
                            self = .ChatItem_StandardMessage_WithAttachments
                        } else {
                            self = .ChatItem_StandardMessage
                        }

                    case .updateMessage(let updateMessage):
                        switch updateMessage.update {
                        case .simpleUpdate:
                            self = .ChatItem_ChatUpdateMessage_SimpleUpdate
                        case .groupChange:
                            self = .ChatItem_ChatUpdateMessage_GroupChange
                        case .expirationTimerChange:
                            self = .ChatItem_ChatUpdateMessage_ExpirationTimerChange
                        case .profileChange:
                            self = .ChatItem_ChatUpdateMessage_ProfileChange
                        case .threadMerge:
                            self = .ChatItem_ChatUpdateMessage_ThreadMerge
                        case .sessionSwitchover:
                            self = .ChatItem_ChatUpdateMessage_SessionSwitchover
                        case .learnedProfileChange:
                            self = .ChatItem_ChatUpdateMessage_LearnedProfileChange
                        case .groupCall:
                            self = .ChatItem_ChatUpdateMessage_GroupCall
                        case .individualCall:
                            self = .ChatItem_ChatUpdateMessage_IndividualCall
                        case .none:
                            // We don't restore and therefore don't benchmark these.
                            return nil
                        }
                    }
                }
            }
        }

        enum PostFrameRestoreAction: String, CaseIterable {
            case InsertContactHiddenInfoMessage
            case UpdateThreadMetadata
            case EnqueueAvatarFetch
            case IndexThreads
        }
    }
}

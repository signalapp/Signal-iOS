//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {

    // MARK: -

    /// A `Bencher` specialized for measuring Backup archiving.
    class ArchiveBencher: Bencher {
        override init(
            dateProviderMonotonic: @escaping DateProviderMonotonic,
            memorySampler: any MemorySampler
        ) {
            super.init(
                dateProviderMonotonic: dateProviderMonotonic,
                memorySampler: memorySampler
            )
        }

        /// Given a block that does an enumeration over db objects, wraps that enumeration to instead take
        /// a closure with a FrameBencher that also measures the time spent enumerating.
        func wrapEnumeration<EnumeratedInput, Output>(
            _ enumerationFunc: (DBReadTransaction, (EnumeratedInput) throws -> Output) throws -> Void,
            tx: DBReadTransaction,
            enumerationBlock: @escaping (EnumeratedInput, FrameBencher) throws -> Output
        ) rethrows {
            var enumerationStepStartDate = dateProvider()
            try enumerationFunc(tx) { enumeratedInput throws in
                defer {
                    // A little cheating - the "end" of this step is the "start"
                    // of the next one.
                    enumerationStepStartDate = dateProvider()
                }

                let frameBencher = FrameBencher(
                    bencher: self,
                    dateProvider: dateProvider,
                    enumerationStepStartDate: enumerationStepStartDate
                )

                return try enumerationBlock(enumeratedInput, frameBencher)
            }
        }

        /// Variant of the above where the block doesn't throw; unfortunately `rethrows`
        /// can't cover two layers of throws variations.
        func wrapEnumeration<EnumeratedInput, Output>(
            _ enumerationFunc: (DBReadTransaction, (EnumeratedInput) -> Output) throws -> Void,
            tx: DBReadTransaction,
            enumerationBlock: @escaping (EnumeratedInput, FrameBencher) -> Output
        ) rethrows {
            var enumerationStepStartDate = dateProvider()
            try enumerationFunc(tx) { enumeratedInput in
                defer {
                    // A little cheating - the "end" of this step is the "start"
                    // of the next one.
                    enumerationStepStartDate = dateProvider()
                }

                let frameBencher = FrameBencher(
                    bencher: self,
                    dateProvider: dateProvider,
                    enumerationStepStartDate: enumerationStepStartDate
                )

                return enumerationBlock(enumeratedInput, frameBencher)
            }
        }
    }

    // MARK: -

    /// A `Bencher` specialized for measuring Backup restoring.
    class RestoreBencher: Bencher {
        enum PreFrameRestoreAction: String {
            case DropInteractionIndexes
        }

        enum PostFrameRestoreAction: String {
            case InsertContactHiddenInfoMessage
            case InsertPhoneNumberMissingAci
            case UpdateThreadMetadata
            case EnqueueAvatarFetch
            case IndexThreads
            case RecreateInteractionIndexes
        }

        private let dbFileSizeBencher: DBFileSizeBencher?

        private var preFrameRestoreMetrics = [PreFrameRestoreAction: Metrics]()
        private var postFrameRestoreMetrics = [PostFrameRestoreAction: Metrics]()

        init(
            dateProviderMonotonic: @escaping DateProviderMonotonic,
            dbFileSizeProvider: any DBFileSizeProvider,
            memorySampler: any MemorySampler
        ) {
            self.dbFileSizeBencher = if FeatureFlags.messageBackupDetailedBenchLogging {
                DBFileSizeBencher(dateProvider: dateProviderMonotonic, dbFileSizeProvider: dbFileSizeProvider)
            } else {
                nil
            }

            super.init(
                dateProviderMonotonic: dateProviderMonotonic,
                memorySampler: memorySampler
            )
        }

        override fileprivate func frameBencherDidProcessFrame(
            _ frameBencher: MessageBackup.Bencher.FrameBencher,
            frame: BackupProto_Frame,
            frameProcessingDurationMs: UInt64,
            enumerationStepDurationMs: UInt64?
        ) {
            super.frameBencherDidProcessFrame(
                frameBencher,
                frame: frame,
                frameProcessingDurationMs: frameProcessingDurationMs,
                enumerationStepDurationMs: enumerationStepDurationMs
            )

            dbFileSizeBencher?.logIfNecessary(totalFramesProcessed: totalFramesProcessed)
        }

        override func logResults() {
            Logger.info("Pre-Frame Restore Metrics:")
            for (action, metrics) in self.preFrameRestoreMetrics.sorted(by: { $0.value.totalDurationMs > $1.value.totalDurationMs }) {
                logMetrics(metrics, typeString: action.rawValue)
            }

            super.logResults()

            Logger.info("Post-Frame Restore Metrics:")
            for (action, metrics) in self.postFrameRestoreMetrics.sorted(by: { $0.value.totalDurationMs > $1.value.totalDurationMs }) {
                logMetrics(metrics, typeString: action.rawValue)
            }
        }

        // MARK: -

        func benchPreFrameRestoreAction<T>(_ action: PreFrameRestoreAction, _ block: () throws -> T) rethrows -> T {
            return try benchAction(action, actionMetricsKeyPath: \.preFrameRestoreMetrics, block: block)
        }

        func benchPostFrameRestoreAction<T>(_ action: PostFrameRestoreAction, _ block: () throws -> T) rethrows -> T {
            return try benchAction(action, actionMetricsKeyPath: \.postFrameRestoreMetrics, block: block)
        }

        /// Measures the clock time spent in the provided block.
        private func benchAction<Action: Hashable, T>(
            _ action: Action,
            actionMetricsKeyPath: ReferenceWritableKeyPath<RestoreBencher, [Action: Metrics]>,
            block: () throws -> T
        ) rethrows -> T {
            let startDate = dateProvider()
            let result = try block()
            let durationMs = dateProvider().millisSince(startDate)

            var metrics = self[keyPath: actionMetricsKeyPath][action] ?? Metrics()
            metrics.frameCount += 1
            metrics.totalDurationMs += durationMs
            metrics.maxDurationMs = max(durationMs, metrics.maxDurationMs)
            self[keyPath: actionMetricsKeyPath][action] = metrics

            return result
        }

        class DBFileSizeBencher {
            private let dateProvider: DateProviderMonotonic
            private let dbFileSizeProvider: DBFileSizeProvider
#if DEBUG
            private let secondsBetweenLogs: UInt64 = 2
#else
            private let secondsBetweenLogs: UInt64 = 15
#endif

            /// The last time we logged.
            private var lastLogDate: MonotonicDate?
            /// The number of total frames the last time we logged.
            private var lastTotalFramesProcessed: UInt64?

            init(
                dateProvider: @escaping DateProviderMonotonic,
                dbFileSizeProvider: DBFileSizeProvider
            ) {
                self.dateProvider = dateProvider
                self.dbFileSizeProvider = dbFileSizeProvider
            }

            func logIfNecessary(totalFramesProcessed: UInt64) {
                if
                    let lastLogDate,
                    dateProvider().millisSince(lastLogDate) < secondsBetweenLogs * MSEC_PER_SEC
                {
                    // Bail if we logged recently.
                    return
                }

                let dbFileSize = dbFileSizeProvider.getDatabaseFileSize()
                let walFileSize = dbFileSizeProvider.getDatabaseWALFileSize()
                Logger.info("{DB:\(dbFileSize), WAL:\(walFileSize), frames:\(totalFramesProcessed), framesDelta:\(totalFramesProcessed - (lastTotalFramesProcessed ?? 0))}")

                lastLogDate = dateProvider()
                lastTotalFramesProcessed = totalFramesProcessed
            }
        }
    }

    // MARK: -

    /// A base class for measuring and logging clock time spent in Backup
    /// archive/restore, per frame type.
    class Bencher {
        fileprivate let dateProvider: DateProviderMonotonic
        fileprivate let memorySampler: MemorySampler

        fileprivate let startDate: MonotonicDate

        fileprivate var totalFramesProcessed: UInt64 = 0
        fileprivate var frameProcessingMetrics = [FrameType: Metrics]()

        fileprivate init(
            dateProviderMonotonic: @escaping DateProviderMonotonic,
            memorySampler: MemorySampler
        ) {
            self.dateProvider = dateProviderMonotonic
            self.memorySampler = memorySampler

            startDate = dateProviderMonotonic()
        }

        fileprivate func frameBencherDidProcessFrame(
            _ frameBencher: FrameBencher,
            frame: BackupProto_Frame,
            frameProcessingDurationMs: UInt64,
            enumerationStepDurationMs: UInt64?
        ) {
            memorySampler.sample()

            guard let frameType = FrameType(frame: frame) else {
                return
            }

            let durationMs = dateProvider().millisSince(frameBencher.startDate)
            totalFramesProcessed += 1

            var metrics = frameProcessingMetrics[frameType] ?? Metrics()
            metrics.frameCount += 1
            metrics.totalDurationMs += durationMs
            metrics.maxDurationMs = max(durationMs, metrics.maxDurationMs)
            metrics.totalEnumerationDurationMs += enumerationStepDurationMs ?? 0

            if durationMs > Metrics.durationWarningThresholdMs {
                metrics.frameCountAboveDurationWarningThreshold += 1

                if FeatureFlags.messageBackupDetailedBenchLogging {
                    metrics.universalFrameCountWhenAboveWarningThreshold.append(totalFramesProcessed)
                }
            }

            frameProcessingMetrics[frameType] = metrics
        }

        // MARK: -

        /// Measures the clock time spent in the provided block.
        ///
        /// The provided block takes a ``FrameBencher`` which can itself be provided the
        /// ``BackupProto_Frame``; this is done so the return type doesn't have to be a frame.
        func processFrame<T>(_ block: (FrameBencher) throws -> T) rethrows -> T {
            let frameBencher = FrameBencher(
                bencher: self,
                dateProvider: dateProvider,
                enumerationStepStartDate: nil
            )

            return try block(frameBencher)
        }

        /// For measuring processing (import or export) of a single frame.
        class FrameBencher {
            private let bencher: Bencher
            private let dateProvider: DateProviderMonotonic

            /// The time at which processing began for a frame.
            fileprivate let startDate: MonotonicDate

            /// If present, represents the time at which an enumeration method
            /// was asked to produce an element that resulted in the frame whose
            /// processing is being measured by this `FrameBencher`.
            ///
            /// Subtracting this time from `startDate` represents the amount of
            /// time spent taking the enumeration step that produced the model
            /// resulting in the frame.
            private let enumerationStepStartDate: MonotonicDate?

            fileprivate init(
                bencher: Bencher,
                dateProvider: @escaping DateProviderMonotonic,
                enumerationStepStartDate: MonotonicDate?
            ) {
                self.bencher = bencher
                self.dateProvider = dateProvider
                self.startDate = dateProvider()
                self.enumerationStepStartDate = enumerationStepStartDate
            }

            func didProcessFrame(_ frame: BackupProto_Frame) {
                bencher.frameBencherDidProcessFrame(
                    self,
                    frame: frame,
                    frameProcessingDurationMs: dateProvider().millisSince(startDate),
                    enumerationStepDurationMs: enumerationStepStartDate.map { startDate.millisSince($0) }
                )
            }
        }

        // MARK: -

        func logResults() {
            let totalFrameCount = frameProcessingMetrics.reduce(0, { $0 + $1.value.frameCount })
            Logger.info("Processed \(loggableCountString(totalFrameCount)) frames in \(dateProvider().millisSince(startDate))ms")

            Logger.info("Frame Processing Metrics:")
            for (frameType, metrics) in self.frameProcessingMetrics.sorted(by: { $0.value.totalDurationMs > $1.value.totalDurationMs }) {
                logMetrics(metrics, typeString: frameType.rawValue)
            }
        }

        fileprivate func logMetrics(_ metrics: Metrics, typeString: String) {
            guard metrics.frameCount > 0 else { return }
            var logString = "\(loggableCountString(metrics.frameCount)) \(typeString)(s) in \(metrics.totalDurationMs)ms."
            if metrics.frameCount > 1 {
                logString += " Avg:\(metrics.totalDurationMs / metrics.frameCount)ms"
                logString += " Max:\(metrics.maxDurationMs)ms"
            }
            if metrics.totalEnumerationDurationMs > 0 {
                logString += " Enum:\(metrics.totalEnumerationDurationMs)ms"
            }
            if metrics.frameCountAboveDurationWarningThreshold > 0 {
                logString += " AboveThreshold:\(metrics.frameCountAboveDurationWarningThreshold)"
            }
            if metrics.universalFrameCountWhenAboveWarningThreshold.count > 0 {
                let percentileStrings = Percentile.computePercentiles(values: metrics.universalFrameCountWhenAboveWarningThreshold)
                    .map { (percentile, totalFrameCount) in "p\(percentile.rawValue):\(totalFrameCount)" }

                logString += " UnivFrameCountWhenAboveThreshold:{\(percentileStrings.joined(separator: ","))}"
            }
            Logger.info(logString)
        }

        private func loggableCountString(_ number: UInt64) -> String {
            if FeatureFlags.messageBackupDetailedBenchLogging {
                return "\(number)"
            }

            // Only log the order of magnitude and most significant digit, e.g.
            // "~50000" instead of "54321".
            var magnitude: UInt64 = 1
            while magnitude <= number {
                magnitude *= 10
            }
            let nearestOrderOfMagnitude = magnitude / 10
            let mostSignificantDigit = number / nearestOrderOfMagnitude

            return "~\(mostSignificantDigit * nearestOrderOfMagnitude)"
        }

        fileprivate struct Metrics {
            static let durationWarningThresholdMs: UInt64 = 30

            var frameCount: UInt64 = 0
            var frameCountAboveDurationWarningThreshold: UInt64 = 0
            var totalDurationMs: UInt64 = 0
            var maxDurationMs: UInt64 = 0
            var totalEnumerationDurationMs: UInt64 = 0

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

        fileprivate enum FrameType: String {
            case AccountData

            case Recipient_Contact
            case Recipient_Group
            case Recipient_DistributionList
            case Recipient_Self
            case Recipient_CallLink
            case Recipient_ReleaseNotes

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

            case NotificationProfile

            case ChatFolder

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
                case .notificationProfile:
                    self = .NotificationProfile
                case .chatFolder:
                    self = .ChatFolder
                case nil:
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
                    case .releaseNotes:
                        self = .Recipient_ReleaseNotes
                    case nil:
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
                    case nil:
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
                        case nil:
                            return nil
                        }
                    }
                }
            }
        }
    }
}

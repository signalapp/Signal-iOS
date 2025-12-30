//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension BackupArchive {

    // MARK: -

    /// A `Bencher` specialized for measuring Backup archiving.
    class ArchiveBencher: Bencher {

        /// Given a block that does an enumeration over db objects, wraps that enumeration to instead take
        /// a closure with a FrameBencher that also measures the time spent enumerating.
        func wrapEnumeration<EnumeratedInput, Output>(
            _ enumerationFunc: (DBReadTransaction, (EnumeratedInput) throws -> Output) throws -> Void,
            tx: DBReadTransaction,
            enumerationBlock: @escaping (EnumeratedInput, FrameBencher) throws -> Output,
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
                    enumerationStepStartDate: enumerationStepStartDate,
                )

                return try enumerationBlock(enumeratedInput, frameBencher)
            }
        }

        /// Variant of the above where the block doesn't throw; unfortunately `rethrows`
        /// can't cover two layers of throws variations.
        func wrapEnumeration<EnumeratedInput, Output>(
            _ enumerationFunc: (DBReadTransaction, (EnumeratedInput) -> Output) throws -> Void,
            tx: DBReadTransaction,
            enumerationBlock: @escaping (EnumeratedInput, FrameBencher) -> Output,
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
                    enumerationStepStartDate: enumerationStepStartDate,
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

        private var preFrameRestoreMetrics = [PreFrameRestoreAction: Metrics]()
        private var postFrameRestoreMetrics = [PostFrameRestoreAction: Metrics]()

        override func logResults() {
            logger.info("Pre-Frame Restore Metrics:")
            for (action, metrics) in self.preFrameRestoreMetrics.sorted(by: { $0.value.totalDurationMs > $1.value.totalDurationMs }) {
                logMetrics(metrics, typeString: action.rawValue)
            }

            super.logResults()

            logger.info("Post-Frame Restore Metrics:")
            for (action, metrics) in self.postFrameRestoreMetrics.sorted(by: { $0.value.totalDurationMs > $1.value.totalDurationMs }) {
                logMetrics(metrics, typeString: action.rawValue)
            }
        }

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
            block: () throws -> T,
        ) rethrows -> T {
            let startDate = dateProvider()
            let result = try block()
            let durationNanos = (dateProvider() - startDate).nanoseconds

            var metrics = self[keyPath: actionMetricsKeyPath][action] ?? Metrics()
            metrics.frameCount += 1
            metrics.totalDurationNanos += durationNanos
            metrics.maxDurationNanos = max(durationNanos, metrics.maxDurationNanos)
            self[keyPath: actionMetricsKeyPath][action] = metrics

            return result
        }
    }

    // MARK: -

    /// A base class for measuring and logging clock time spent in Backup
    /// archive/restore, per frame type.
    class Bencher {
        fileprivate let dateProvider: DateProviderMonotonic
        fileprivate let logger: PrefixedLogger
        fileprivate let memorySampler: MemorySampler

        fileprivate let startDate: MonotonicDate
        fileprivate var totalFramesProcessed: UInt64 = 0
        fileprivate var frameProcessingMetrics = [FrameType: Metrics]()

        init(
            dateProviderMonotonic: @escaping DateProviderMonotonic,
            memorySampler: MemorySampler,
        ) {
            self.dateProvider = dateProviderMonotonic
            self.logger = PrefixedLogger(prefix: "[Backups]")
            self.memorySampler = memorySampler

            startDate = dateProviderMonotonic()
        }

        fileprivate func frameBencherDidProcessFrame(
            _ frameBencher: FrameBencher,
            frame: BackupProto_Frame,
            frameProcessingDurationNanos: UInt64,
            enumerationStepDurationNanos: UInt64?,
        ) {
            memorySampler.sample()

            guard let frameType = FrameType(frame: frame) else {
                return
            }

            totalFramesProcessed += 1

            var metrics = frameProcessingMetrics[frameType] ?? Metrics()
            metrics.frameCount += 1
            metrics.totalDurationNanos += frameProcessingDurationNanos
            metrics.maxDurationNanos = max(frameProcessingDurationNanos, metrics.maxDurationNanos)
            metrics.totalEnumerationDurationNanos += enumerationStepDurationNanos ?? 0
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
                enumerationStepStartDate: nil,
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
                enumerationStepStartDate: MonotonicDate?,
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
                    frameProcessingDurationNanos: (dateProvider() - startDate).nanoseconds,
                    enumerationStepDurationNanos: enumerationStepStartDate.map { (startDate - $0).nanoseconds },
                )
            }
        }

        // MARK: -

        func logResults() {
            let totalFrameCount = frameProcessingMetrics.reduce(0, { $0 + $1.value.frameCount })
            logger.info("Processed \(loggableCountString(totalFrameCount)) frames in \((dateProvider() - startDate).milliseconds)ms")

            logger.info("Frame Processing Metrics:")
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
            logger.info(logString)
        }

        private func loggableCountString(_ number: UInt64) -> String {
            if BuildFlags.Backups.detailedBenchLogging {
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
            var frameCount: UInt64 = 0
            var totalDurationNanos: UInt64 = 0
            var maxDurationNanos: UInt64 = 0
            var totalEnumerationDurationNanos: UInt64 = 0

            var totalDurationMs: UInt64 { totalDurationNanos / NSEC_PER_MSEC }
            var maxDurationMs: UInt64 { maxDurationNanos / NSEC_PER_MSEC }
            var totalEnumerationDurationMs: UInt64 { totalEnumerationDurationNanos / NSEC_PER_MSEC }
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
            case ChatItem_ChatUpdateMessage_PollTerminate
            case ChatItem_ChatUpdateMessage_PinMessage

            case ChatItem_PaymentNotification
            case ChatItem_GiftBadge
            case ChatItem_ViewOnceMessage
            case ChatItem_DirectStoryReplyMessage
            case ChatItem_Poll

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
                    case .poll:
                        self = .ChatItem_Poll
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
                        case .pollTerminate:
                            self = .ChatItem_ChatUpdateMessage_PollTerminate
                        case .pinMessage:
                            self = .ChatItem_ChatUpdateMessage_PinMessage
                        case nil:
                            return nil
                        }
                    }
                }
            }
        }
    }
}

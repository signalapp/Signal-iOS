//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {

    /// Used to measure and log backup import/export clock time per frame type.
    /// Per-frame metrics exclude time spent in backup file I/O and proto serialization;
    /// this measures time spent reading/writing to our DB and doing CPU processing.
    class Bencher {

        private let dateProvider: DateProvider

        let startTimestamp: UInt64

        init(dateProvider: @escaping DateProvider) {
            self.dateProvider = dateProvider
            self.startTimestamp = dateProvider().ows_millisecondsSince1970
        }

        /// Measures the clock time spent in the provided block.
        ///
        /// The provided block takes a ``FrameBencher`` which can itself be provided the
        /// ``BackupProto_Frame``; this is done so the return type doesn't have to be a frame.
        func processFrame<T>(_ block: (FrameBencher) throws -> T) rethrows -> T {
            let startMs = dateProvider().ows_millisecondsSince1970
            let frameBencher = FrameBencher(bencher: self, beforeEnumerationStartMs: nil, startMs: startMs)
            return try block(frameBencher)
        }

        /// Measures the clock time spent in the provided block.
        func benchPostFrameAction(_ action: PostFrameRestoreAction, _ block: () throws -> Void) rethrows -> Void {
            let startMs = dateProvider().ows_millisecondsSince1970
            try block()
            let durationMs = dateProvider().ows_millisecondsSince1970 - startMs
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
            var beforeEnumerationStartMs = dateProvider().ows_millisecondsSince1970
            try enumerationFunc(input) { t in
                let enumerationStartMs = self.dateProvider().ows_millisecondsSince1970
                let frameBencher = FrameBencher(
                    bencher: self,
                    beforeEnumerationStartMs: beforeEnumerationStartMs,
                    startMs: enumerationStartMs
                )
                let output = try block(t, frameBencher)
                beforeEnumerationStartMs = self.dateProvider().ows_millisecondsSince1970
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
            var beforeEnumerationStartMs = dateProvider().ows_millisecondsSince1970
            try enumerationFunc(input) { t in
                let enumerationStartMs = self.dateProvider().ows_millisecondsSince1970
                let frameBencher = FrameBencher(
                    bencher: self,
                    beforeEnumerationStartMs: beforeEnumerationStartMs,
                    startMs: enumerationStartMs
                )
                let output = block(t, frameBencher)
                beforeEnumerationStartMs = self.dateProvider().ows_millisecondsSince1970
                return output
            }
        }

        /// For measuring processing (import or export) of a single frame.
        class FrameBencher {
            // A bit confusing but if present, this measures the time spent by the
            // enumeration itself (reading the db, deserializing records)
            // versus startMs below is the time spent in the enumeration block.
            private let beforeEnumerationStartMs: UInt64?
            private let startMs: UInt64
            private let bencher: Bencher

            fileprivate init(bencher: Bencher, beforeEnumerationStartMs: UInt64?, startMs: UInt64) {
                self.bencher = bencher
                self.beforeEnumerationStartMs = beforeEnumerationStartMs
                self.startMs = startMs
            }

            func didProcessFrame(_ frame: BackupProto_Frame) {
                guard let frameType = FrameType(frame: frame) else {
                    return
                }
                let durationMs = bencher.dateProvider().ows_millisecondsSince1970 - startMs
                var metrics = bencher.metrics[frameType] ?? Metrics()
                metrics.frameCount += 1
                metrics.totalDurationMs += durationMs
                metrics.maxDurationMs = max(durationMs, metrics.maxDurationMs)
                if let beforeEnumerationStartMs {
                    metrics.totalEnumerationDurationMs += startMs - beforeEnumerationStartMs
                }
                bencher.metrics[frameType] = metrics
            }
        }

        func logResults() {
            let totalFrameCount = metrics.reduce(0, { $0 + $1.value.frameCount })
            Logger.info("Processed \(loggableCountString(totalFrameCount)) frames in \(dateProvider().ows_millisecondsSince1970 - self.startTimestamp)ms")

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

        private var metrics = [FrameType: Metrics]()
        private var postFrameMetrics = [PostFrameRestoreAction: Metrics]()

        private struct Metrics {
            var frameCount: UInt64 = 0
            var totalDurationMs: UInt64 = 0
            var maxDurationMs: UInt64 = 0
            var totalEnumerationDurationMs: UInt64 = 0
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
            case ChatItem_ChatUpdateMessage_IndividualCall
            case ChatItem_ChatUpdateMessage_GroupCall

            case ChatItem_PaymentNotification
            case ChatItem_GiftBadge
            case ChatItem_ViewOnceMessage

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
                        case
                            .simpleUpdate,
                            .groupChange,
                            .expirationTimerChange,
                            .profileChange,
                            .threadMerge,
                            .sessionSwitchover,
                            .learnedProfileChange,
                            .none:
                            self = .ChatItem_ChatUpdateMessage
                        case .groupCall:
                            self = .ChatItem_ChatUpdateMessage_GroupCall
                        case .individualCall:
                            self = .ChatItem_ChatUpdateMessage_IndividualCall
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

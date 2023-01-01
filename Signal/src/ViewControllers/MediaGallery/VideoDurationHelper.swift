//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Foundation
import SignalServiceKit

/// Manages the work of determining the duration of videos. Takes care of caching, avoiding
/// duplicate effort, discarding unneeded requests, and reordering requests in LIFO order.
class VideoDurationHelper {
    static let shared = VideoDurationHelper()

    /// The only exception this class throws.
    class DurationUnavailableError: Error {
    }

    /// Represents the lifetime of a client. See `with(context:,closure:)` for proper usage.
    class Context {
    }

    /// Potentially slow operations, such as creating a SignalAttachment or analyzing a video file,
    /// happen on this serial queue.
    private let queue = ReverseDispatchQueue(label: "org.signal.video-duration-helper",
                                             qos: .utility,
                                             autoreleaseFrequency: .inherit)

    /// One of these exists for each attachment whose video duration is going to be computed.
    private struct PendingPromise {
        var promise: Promise<TimeInterval>
        // So long as any of these is non-nil, the result is still needed.
        var contexts = WeakArray<Context>()
    }

    /// Holds existing unsealed promises to avoid duplicate effort if we're asked for the same video
    /// twice in quick succession.
    /// Guarded by `lock`.
    private var pendingPromises: [String: PendingPromise] = [:]
    private var lock = UnfairLock()

    /// A stack of contexts. This array is never empty. See `with(context:,closure:)` for more.
    private var contexts: [Context]

    /// Clients who don't use `with(context:,closure:)` get this context by default. It is never
    /// deinited so a result is guaranteed to be provided eventually.
    private let defaultContext = Context()

    private var currentContext: Context {
        return contexts.last!
    }

    init() {
        contexts = [defaultContext]
    }

    // MARK: - APIs

    /// Returns a promise of the attachment's video's duration.
    /// The promise may be rejected if the duration cannot be determined. The duration is saved to
    /// the database so that subsequent lookups will be fast.
    func promisedDuration(attachment: TSAttachmentStream) -> Promise<TimeInterval> {
        dispatchPrecondition(condition: .onQueue(.main))

        if let promise = alreadySealedPromiseForSavedDuration(for: attachment) {
            return promise
        }
        return lock.withLock {
            if let promise = pendingPromise(attachment) {
                return promise
            }
            return self.makePromise(for: attachment)
        }
    }

    /// Use this to discard queued work when it's no longer needed. As long as the Context is a
    /// valid objects, durations requested during `closure` will eventually be computed. Once
    /// `context` gets deinit'ed, any outstanding promises will be rejected.
    /// Usage:
    ///    class MyViewController: UIViewController {
    ///        let context = VideoDurationHelper.Context()
    ///        func printDuration(attachment: TSAttachmentStream) {
    ///            VideoDurationHelper.shared.with(context: context) {
    ///                VideoDurationHelper.shared.promisedDuration(attachment).then {
    ///                    print("Duration is \($0)")
    ///                }
    ///            }
    ///        }
    ///    }
    func with(context: Context, closure: () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))

        contexts.append(context)
        closure()
        contexts.removeLast()
    }

    // MARK: - Private Methods

    /// If the database already has a duration saved for this attachment, this method returns a
    /// sealed promise. Otherwise, returns nil.
    private func alreadySealedPromiseForSavedDuration(for attachment: TSAttachmentStream) -> Promise<TimeInterval>? {
        guard let duration = attachment.videoDuration?.doubleValue else {
            return nil
        }
        if duration.isNaN {
            return Promise(error: DurationUnavailableError())
        }
        // The database contains a valid duration.
        return Promise.value(duration)
    }

    /// Returns a promise if one already exists in `pendingPromises`. If one is found, the current
    /// context is added to it.
    private func pendingPromise(_ attachment: TSAttachmentStream) -> Promise<TimeInterval>? {
        lock.assertOwner()

        let uniqueId = attachment.uniqueId
        guard let pendingPromise = pendingPromises[uniqueId] else {
            return nil
        }
        // We are already computing a duration for this attachment so there is no need to create a
        // new promise. Add this context so that if the work hasn't already begun, the destruction
        // of the original context won't prevent the promise from being sealed.
        pendingPromises[uniqueId]?.contexts.append(currentContext)

        return pendingPromise.promise
    }

    /// Creates a new promise.
    private func makePromise(for attachment: TSAttachmentStream) -> Promise<TimeInterval> {
        lock.assertOwner()

        guard let cloneRequest = try? attachment.cloneAsSignalAttachmentRequest() else {
            return Promise<TimeInterval>(error: DurationUnavailableError())
        }

        // `context` is weak in case it gets deinitialized before we call
        // `computeDurationIfResultStillNeeded`.
        weak var context = currentContext
        let group = DispatchGroup()
        group.enter()
        let promise = Promise<TimeInterval> { future in
            queue.async {
                // Kick of a possibly asynchronous operation that will eventually resolve or reject
                // the future.
                self.computeDurationIfResultStillNeeded(future: future,
                                                        context: context,
                                                        cloneRequest: cloneRequest)
                // Block to ensure we only compute one duration at a time.
                group.wait()
            }
        }
        promise.observe { _ in
            // Allow the next block on `queue` to run.
            group.leave()
        }
        addPendingPromise(promise, context: context, uniqueId: cloneRequest.uniqueId)
        return promise
    }

    /// Update `pendingPromises` to include this newly created promise.
    private func addPendingPromise(_ promise: Promise<TimeInterval>,
                                   context: Context?, uniqueId: String) {
        lock.assertOwner()

        pendingPromises[uniqueId] = PendingPromise(promise: promise)
        if let context {
            pendingPromises[uniqueId]?.contexts.append(context)
        }
    }

    /// Reject the future if the result is no longer needed or else try to resolve it by analyzing
    /// the video.
    /// Runs on `queue`.
    private func computeDurationIfResultStillNeeded(future: Future<TimeInterval>,
                                                    context: Context?,
                                                    cloneRequest: TSAttachmentStream.CloneAsSignalAttachmentRequest) {
        rejectIfResultNoLongerNeeded(future: future,
                                     uniqueId: cloneRequest.uniqueId,
                                     context: context)
        if future.isSealed {
            return
        }
        self.computeDuration(cloneRequest, future: future)
    }

    /// Reject the future if nobody is left who wants this video's duration.
    /// Runs on `queue`.
    private func rejectIfResultNoLongerNeeded(future: Future<TimeInterval>,
                                              uniqueId: String,
                                              context: Context?) {
        guard context == nil else {
            return
        }
        return self.lock.withLock {
            if !self.hasValidPendingPromise(uniqueId) {
                future.reject(DurationUnavailableError())
                self.pendingPromises.removeValue(forKey: uniqueId)
            }
        }
    }

    /// Is there an entry in `pendingPromises` that still cares about the result?
    /// Runs on `queue`.
    private func hasValidPendingPromise(_ uniqueId: String) -> Bool {
        lock.assertOwner()

        pendingPromises[uniqueId]?.contexts.cullExpired()
        return (pendingPromises[uniqueId]?.contexts.weakReferenceCount ?? 0) > 0
    }

    /// Intermediate result of computing a video's duration.
    private struct Result {
        var duration: TimeInterval?
        // Note: while it would be nice to pass the TSAttachmentStream object around, I ran into
        // some inexplicable behavior (object appears to gets deinit'ed despite a strong reference)
        // which I'm blaming on it not wanting to cross dispatch queues. Therefore, we'll just keep
        // its unique ID around and re-fetch it prior to updating.
        var attachmentUniqueId: String
        var future: Future<TimeInterval>
    }

    /// Runs on self.queue. This is expensive. This will update the database, resolve or reject the
    /// future, and finally call `completion`.
    private func computeDuration(_ cloneRequest: TSAttachmentStream.CloneAsSignalAttachmentRequest,
                                 future: Future<TimeInterval>) {
        var result = Result(attachmentUniqueId: cloneRequest.uniqueId, future: future)
        do {
            /// This is potentially slow.
            let signalAttachment = try TSAttachmentStream.cloneAsSignalAttachment(
                                           request: cloneRequest)
            guard let url = signalAttachment.dataUrl else {
                save(result)
                return
            }
            AVURLAsset.loadDuration(url: url) { duration in
                // Warning! We might be in AVFoundation's private queue.

                // A dirty trick to make `url` remain valid until we're all done. Once
                // `signalAttachment` gets deinit'ed, it unlinks its file.
                withExtendedLifetime(signalAttachment) { }

                result.duration = duration
                self.save(result)
            }
        } catch {
            save(result)
        }
    }

    /// Runs on self.queue. If `result.duration` is nil it is considered a failure.
    private func save(_ result: Result) {
        SDSDatabaseStorage.shared.write { transaction in
            if let attachment = TSAttachmentStream.anyFetchAttachmentStream(uniqueId: result.attachmentUniqueId,
                                                                            transaction: transaction) {
                attachment.update(withVideoDuration: NSNumber(value: result.duration ?? Double.nan),
                                  transaction: transaction)
            }
        }
        self.lock.withLock {
            if let duration = result.duration {
                result.future.resolve(duration)
            } else {
                result.future.reject(DurationUnavailableError())
            }
            self.pendingPromises.removeValue(forKey: result.attachmentUniqueId)
        }
    }
}

/// AVURLAsset has no ability to do error checking prior to iOS 15. This extension makes it easy to
/// get the duration with good error checking on modern iOS and hacky error checking on legacy
/// versions. Please delete this when we drop iOS 14.
extension AVURLAsset {
    static func loadDuration(url: URL, completion: @escaping (TimeInterval?) -> Void) {
        if #available(iOS 15.0, *) {
            modernDuration(url: url, completion: completion)
            return
        }
        legacyDuration(url: url, completion: completion)
    }

    @available(iOS 15, *)
    private static func modernDuration(url: URL, completion: @escaping (TimeInterval?) -> Void) {
        Task {
            let sourceAsset = AVURLAsset(url: url)
            do {
                let duration = try await sourceAsset.load(.duration)
                completion(CMTimeGetSeconds(duration))
            } catch {
                completion(nil)
            }
        }
    }

    private static func legacyDuration(url: URL, completion: @escaping (TimeInterval?) -> Void) {
        let sourceAsset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(sourceAsset.duration)
        if duration == 0 {
            completion(nil)
        } else {
            completion(duration)
        }
    }
}

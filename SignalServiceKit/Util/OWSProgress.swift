//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A way to report partial progress on async tasks back to the caller; typically used to drive
/// some kind of loading bar UI.
///
/// You create a ``OWSProgressSink``, add ``OWSProgressSource``(s) to that sink,
/// and update progress on the sources as the long running task does its work.
///
/// The API has three goals/principles:
/// 1. Progress from multiple independent sources can be combined into a single net total output progress
/// 2. Adding child progress sources is async-friendly and thread safe
/// 3. Updating a single source is *fast* but **NOT** thread safe
///
/// Of note, workers that increment progress are assumed to be single threaded (or have their own locking).
/// If your worker is multi-threaded, you should probably generate one source per thread or locking context.
///
/// First, call ``OWSProgress/createSink(_:)`` with an observer block which is called with progress updates.
/// **WARNING**: the block is escaping and strongly held by OWSProgressSink. Beware of retain cycles.
///
/// Add one or more sources to the sink with ``OWSProgressSink/addSource(withLabel:unitCount:)``.
/// When you add a source to a sink, you update the sink's total unit count.
/// Units can mean anything; what matters is that updates to sources are measured in units,
/// and progress is reported in units. (Or percentage of units completed, via convenience var).
/// See ``Foundation/NSProgress``, which uses similar "unit" semantics.
///
/// You may add a child sink with ``OWSProgressSink/addChild(withLabel:unitCount:)``.
/// Child sinks have a unit count and can themselves have their own sources (and child sinks).
/// The completed unit count of a child sink is proportional to its children's completed unit count.
/// Put another way:
/// `parent_complete_units = parent_total_units * Sum(child_completed_units) / Sum(child_total_units)`
/// In this way a child's units are independent of its parent's (and counsins') units.
///
/// For example, say you download a file and then write rows to the db.
/// Add two child sinks: "Download" and "Write" , each with a unit count of 50.
/// Add a source to "Download" with unit count of [file byte length].
/// Add a source to "Write" with unit count of [# of rows to write to db].
/// In this way, even though "Download" and "Write" use totally different units, units of progress
/// at the root represent % complete with each counting towards 50% of the work.
/// If we download half the file, the root completed unit count would be 25 (%).
///
/// Note two other implicit advantages in the example above:
/// 1. We can determine the [# of SQL rows to write] _after_ downloading, by adding
///   the Write child at the start (proportioning 50% of the "progress" to it), but only
///   adding its source later after we've downloaded.
/// 2. A DownloadManager can have a download method that takes an ``OWSProgressSink``
///   without knowing or caring whether that sink is itself a root or a child; progress units are
///   re-normalized to parent progress units transparently to callers.
///
/// A note on ``Foundation/NSProgress``.
/// This type _looks_ like NSProgress but behaves very differently.
/// * NSProgress is a class class meant to be updated and observed with KVO.
/// OWSProgress is a snapshot-in-time struct;OWSProgressSink manages observation.
/// * NSProgress uses locks for updates, making rapid updates on a single thread expensive.
/// OWSProgress optimizes for single-threaded updates; batching observer updates to do so efficiently.
/// * NSProgress requires you to know unit counts for all children up-front and they must all share units.
/// OWSProgress lets you add children lazily and renormalizes disparate units at each level of the tree.
public struct OWSProgress: Equatable, SomeOWSProgress {
    public struct SourceProgress: Equatable, SomeOWSProgress {
        /// The completed unit count of this particular source.
        /// The units DO NOT necessarily correspond to the units of the root OWSProgress.
        public let completedUnitCount: UInt64
        /// The total unit count of this particular source.
        /// The units DO NOT necessarily correspond to the units of the root OWSProgress.
        public let totalUnitCount: UInt64
        /// The chain of labels (ending with the source's label) from the root
        /// sink to this particular source.
        public let labels: [String]
    }

    /// The completed unit count across all direct children.
    public let completedUnitCount: UInt64
    /// The total unit count of all direct children.
    public let totalUnitCount: UInt64

    /// All sources at all layers of the progress tree, which have emitted progress values.
    /// Maps from source label to the source.
    public let sourceProgresses: [String: SourceProgress]

    public init(
        completedUnitCount: UInt64,
        totalUnitCount: UInt64,
        sourceProgresses: [String: SourceProgress]
    ) {
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.sourceProgresses = sourceProgresses
    }

#if DEBUG
    public static func forPreview(_ percentComplete: Float) -> OWSProgress {
        return OWSProgress(completedUnitCount: UInt64(percentComplete * 100), totalUnitCount: 100, sourceProgresses: [:])
    }
#endif

    public static var zero: OWSProgress {
        return OWSProgress(completedUnitCount: 0, totalUnitCount: 0, sourceProgresses: [:])
    }

    /// Create a root sink, taking the single observer block of progress updates.
    /// See class docs for this type for usage.
    public static func createSink(_ observer: @escaping OWSProgressSink.Observer) -> OWSProgressSink {
        return OWSProgressRootNode(observer: observer)
    }
}

public protocol SomeOWSProgress {
    var completedUnitCount: UInt64 { get }
    var totalUnitCount: UInt64 { get }
}

extension SomeOWSProgress {
    /// Percentage completion measured as (completedUnitCount / totalUnitCount)
    /// 0 if no children or sources have been added.
    public var percentComplete: Float {
        guard totalUnitCount > 0 else { return 0 }
        return Float(completedUnitCount) / Float(totalUnitCount)
    }

    /// Unit count remaining measured as (totalUnitCount - completedUnitCount).
    /// 0 if no children or sources have been added.
    public var remainingUnitCount: UInt64 {
        guard
            totalUnitCount > 0,
            totalUnitCount >= completedUnitCount
        else {
            return 0
        }

        return totalUnitCount - completedUnitCount
    }

    /// Percent = 1. False if no children or sources have been added.
    public var isFinished: Bool {
        totalUnitCount != 0 && completedUnitCount == totalUnitCount
    }
}

/// Sinks are thread-safe and can have children added from any thread context.
public protocol OWSProgressSink {
    typealias Observer = (OWSProgress) async -> Void

    /// Add a child sink, returning it.
    /// Child sinks contribute to the total unit count of their parent.
    /// A child sink's progress is its own unit count weighted by the completed unit count across all its children.
    /// - precondition: unitCount > 0
    ///
    /// **WARNING** adding a child to a parent sink after some sibling has previously updated progress
    /// results in undefined behavior; old progress values are not renormalized to new total unit counts.
    /// Adding grandchildren is allowed; typically you want to "reserve" proportional unit counts
    /// by adding a child up-front and then adding a grandchild to that child later.
    func addChild(withLabel label: String, unitCount: UInt64) async -> OWSProgressSink

    /// Add a source, returning it.
    /// Sources contribute to the total unit count of their parent.
    /// Sources are **NOT** thread-safe and should only be updated from a single thread or locking context.
    /// - precondition: unitCount > 0
    ///
    /// **WARNING** adding a source to a parent sink after some sibling has previously updated progress
    /// results in undefined behavior; old progress values are not renormalized to new total unit counts.
    /// Adding grandchildren is allowed; typically you want to "reserve" proportional unit counts
    /// by adding a child up-front and then adding a source to that child later.
    func addSource(withLabel label: String, unitCount: UInt64) async -> OWSProgressSource
}

/// Sources are **NOT** thread-safe and should only be updated from a single thread or locking context.
public protocol OWSProgressSource {

    var completedUnitCount: UInt64 { get }
    var totalUnitCount: UInt64 { get }

    /// Increment the completed unit count (which can only go up).
    /// You can pass 0, though that does nothing.
    /// You can also continue to increment past the total unit count; the value
    /// will be internally capped to the total and further updates no-op.
    func incrementCompletedUnitCount(by increment: UInt64)
}

extension OWSProgressSource {
    func complete() {
        incrementCompletedUnitCount(by: totalUnitCount)
    }
}

extension OWSProgressSource where Self: Sendable {

    /// Given some block of asynchronous work, update progress
    /// on the current source periodically (every ``timeInterval`` seconds)
    /// until the work block completes.
    /// Returns with the result of the work block when it completes.
    public func updatePeriodically<T, E>(
        timeInterval: TimeInterval = 0.1,
        estimatedTimeToCompletion: TimeInterval,
        work: @escaping () async throws(E) -> T
    ) async throws(E) -> T {
        let sleepDurationMillis = UInt64(timeInterval * 1000)
        let source = self
        let didComplete = AtomicBool(false, lock: .init())
        let startDate = Date()
        var lastCompletedUnitCount = source.completedUnitCount
        // Minus one so the timer can never complete it.
        let maxTimerCompletedUnitCount = source.totalUnitCount - 1
        let timeToUnitsMultiplier = Double(source.totalUnitCount) / estimatedTimeToCompletion
        let result = await withTaskGroup(of: Optional<Result<T, E>>.self) { taskGroup in
            taskGroup.addTask {
                while !didComplete.get() {
                    try? await Task.sleep(nanoseconds: sleepDurationMillis * NSEC_PER_MSEC)
                    let date = Date()
                    var units = UInt64(date.timeIntervalSince(startDate) * timeToUnitsMultiplier)
                    units = min(maxTimerCompletedUnitCount, units)
                    defer { lastCompletedUnitCount = units }
                    let incrementalUnits = units - lastCompletedUnitCount
                    if incrementalUnits > 0 {
                        source.incrementCompletedUnitCount(by: units)
                    }
                }
                return nil
            }
            taskGroup.addTask {
                let result: Result<T, E>
                do {
                    result = .success(try await work())
                } catch let error as E {
                    didComplete.set(true)
                    return .failure(error)
                } catch {
                    // Impossible; work only throws E
                    fatalError()
                }
                didComplete.set(true)
                source.incrementCompletedUnitCount(by: source.totalUnitCount)
                return result
            }
            while let result = await taskGroup.next() {
                switch result {
                case .none:
                    break
                case .some(let value):
                    return value
                }
            }
            // Impossible to get here; the second task in the group
            // always returns some result.
            fatalError()
        }
        return try result.get()
    }
}

/// Root node for OWSProgress. Does not itself have a unit count or concept of progress;
/// its children define units entirely.
private actor OWSProgressRootNode: OWSProgressSink {

    private var latestEmittedProgress: OWSProgress?
    private let observer: Observer
    private var observerQueue = SerialTaskQueue()

    private var totalDirectChildUnitCount: UInt64 = 0
    /// Children hold strong references to their parent, so parents hold weak references to children.
    /// If callers release children, they can't be updated anyway so no point retaining them.
    private var directChildren = [Weak<OWSProgressChildNode>]()

    private class SourceNode {
        /// Sources hold strong references to their root sink, so the sink must hold weak references to sources.
        /// If callers release sources, they can't be updated anyway so no point retaining them.
        weak var node: OWSProgressSourceNode?
        /// Hold onto the last progress in case
        /// the source gets released e.g. after hitting 100%.
        var lastProgress: OWSProgress.SourceProgress
        var lastCompletedUnitCountMultiplier: Float

        init(node: OWSProgressSourceNode) {
            self.node = node
            self.lastProgress = node.sourceProgress
            self.lastCompletedUnitCountMultiplier = node.completedUnitCountMultiplier
        }
    }

    /// All sources at all nested levels in the tree.
    private var allSources = [SourceNode]()

    fileprivate init(observer: @escaping Observer) {
        self.observer = observer
    }

    func addChild(withLabel label: String, unitCount: UInt64) async -> OWSProgressSink {
        self.totalDirectChildUnitCount += unitCount
        let child = OWSProgressSinkNode(
            label: label,
            parentLabels: [],
            unitCount: unitCount,
            parent: self,
            rootNode: self
        )
        self.directChildren.append(Weak(value: child))
        // Tell all children (including the new one) about the new total unit count.
        await updateUnitCountsOnChildren()
        // Issue a progres update as the total unit count has changed.
        progressDidUpdate()
        return child
    }

    func addSource(withLabel label: String, unitCount: UInt64) async -> OWSProgressSource {
        self.totalDirectChildUnitCount += unitCount
        let source = OWSProgressSourceNode(
            label: label,
            parentLabels: [],
            totalUnitCount: unitCount,
            parent: self,
            rootNode: self
        )
        self.directChildren.append(Weak(value: source))
        // Tell all children (including the new one) about the new total unit count.
        await updateUnitCountsOnChildren()
        self.addSource(source)
        // Issue a progres update as the total unit count has changed.
        progressDidUpdate()
        return source
    }

    fileprivate func addSource(_ source: OWSProgressSourceNode) {
        allSources.append(SourceNode(node: source))
        source.emitProgressIfNeeded()
    }

    private func updateUnitCountsOnChildren() async {
        // Touch each child so it updates its own children's multiplier.
        for child in directChildren {
            // Direct children of the root have a multiplier of 1;
            // 1 unit corresponds to 1 unit on the top-level progress.
            await child.value?.updateCompletedUnitCountMultiplier(1)
        }
    }

    fileprivate func progressDidUpdate() {
        guard allSources.isEmpty.negated else {
            return
        }
        var completedUnitCount: Float = 0
        var sourceProgresses = [String: OWSProgress.SourceProgress]()
        allSources.forEach { sourceNode in
            let sourceProgress = sourceNode.node?.sourceProgress
                ?? sourceNode.lastProgress
            let sourceCompletedUnitCountMultiplier = sourceNode.node?.completedUnitCountMultiplier
                ?? sourceNode.lastCompletedUnitCountMultiplier
            sourceNode.lastProgress = sourceProgress
            sourceNode.lastCompletedUnitCountMultiplier = sourceCompletedUnitCountMultiplier
            sourceProgresses[sourceProgress.labels.last!] = sourceProgress
            completedUnitCount += sourceCompletedUnitCountMultiplier
                * Float(sourceProgress.completedUnitCount)
        }
        let progress = OWSProgress(
            // Round up optimistically.
            completedUnitCount: UInt64(ceil(completedUnitCount)),
            totalUnitCount: totalDirectChildUnitCount,
            sourceProgresses: sourceProgresses
        )
        defer { latestEmittedProgress = progress }

        // Only update the observer if the units changed;
        // label changes are arbitrary and shouldn't trigger updates.
        var progressDidChange = false
        if progress.completedUnitCount != latestEmittedProgress?.completedUnitCount {
            progressDidChange = true
        }
        if progress.totalUnitCount != latestEmittedProgress?.totalUnitCount {
            progressDidChange = true
        }
        if progressDidChange {
            latestEmittedProgress = progress
            observerQueue.enqueue { [observer, progress] in
                await observer(progress)
            }
        }
    }
}

/// Covers both child sinks and sources. Only the root sink is not a child node.
private protocol OWSProgressChildNode {
    var totalUnitCount: UInt64 { get }

    /// This is all implementation details (this protocol is fileprivate) but
    /// read on if you want the nitty-gritty.
    ///
    /// This is confusing and happens in reverse to common sense.
    /// Say we have the following tree (unit counts in parens):
    /// ```
    ///              root
    ///     __________|_____________
    ///    |                       |
    /// source 1 (50)       child sink A (50)
    ///                 ___________|__________
    ///                |                      |
    ///           source 2 (10)         child sink B (10)
    ///                            ___________|__________
    ///                           |                      |
    ///                     source 3 (100)         source 4 (300)
    /// ```
    /// What should the root complete unit count be if all souces' counts are 0,
    /// except source 4 which has progress of 200?
    /// Answer: 13 units.
    /// How do we get there? Source 4 has 200 units, which is half the total
    /// units across the children of sink B (100 + 300 = 400). So it is "worth" half
    /// of B's units, or 5 units. B's siblings have a total unit count of 20, 5/20 = 25%
    /// so it is "worth" 25% of A's units, or 12.5 units, which gets rounded up to 13.
    ///
    /// We could do all these calculations at read time (addind up sibling unit counts and dividing by them),
    /// but we want progress updates to be FAST. So we instead calculate a "multiplier" up front, at
    /// the time we add children, so that we can quickly normalize sources' units at read time.
    /// The multiplier at each level is:
    /// `[parent's multiplier] * ([parent unit count] ÷ [total count across siblings])`
    ///
    /// In this example, source 4's multiplier would be 0.0625 (`10 ÷ (100 + 300) * (50 ÷ (10 + 10))`)
    /// Other multiplers:
    /// source 1 & child A: 1 (root)
    /// source 2 & child B: 2.5 (`50 ÷ (10 + 10)`)
    /// source 3: (same as source 4).
    func updateCompletedUnitCountMultiplier(_ newValue: Float) async
}

/// A sink that is itself a child to another sink.
private actor OWSProgressSinkNode: OWSProgressSink, OWSProgressChildNode {

    /// The chain of labels starting at the root (no label) and ending in this node's label.
    fileprivate nonisolated let labels: [String]
    /// The unit count of this node. Note that child sinks don't have completedUnitCounts
    /// of their own; instead its children determine the unit count as proportion of this total.
    fileprivate nonisolated let totalUnitCount: UInt64

    /// See ``OWSProgressChildNode/updateCompletedUnitCountMultiplier``.
    /// This gets set immediately after initialization before it can possibly be read.
    fileprivate var completedUnitCountMultiplier: Float = 1

    private var totalDirectChildUnitCount: UInt64 = 0
    private var directChildren = [Weak<OWSProgressChildNode>]()

    /// Children hold strong referenced to their parents; as long as callers
    /// hold a reference to some child source (to increment its progress)
    /// the whole tree above that child will be retained.
    private nonisolated let parent: OWSProgressSink
    /// Every node in the tree holds a strong reference to the root (and in turn its observer block).
    /// The root holds only weak references to its children.
    private nonisolated let rootNode: OWSProgressRootNode

    fileprivate init(
        label: String,
        parentLabels: [String],
        unitCount: UInt64,
        parent: OWSProgressSink,
        rootNode: OWSProgressRootNode
    ) {
        self.labels = parentLabels + [label]
        self.totalUnitCount = unitCount
        self.parent = parent
        self.rootNode = rootNode
    }

    func addChild(withLabel label: String, unitCount: UInt64) async -> OWSProgressSink {
        owsAssertDebug(unitCount > 0)
        self.totalDirectChildUnitCount += unitCount
        let child = OWSProgressSinkNode(
            label: label,
            parentLabels: self.labels,
            unitCount: unitCount,
            parent: self,
            rootNode: rootNode
        )
        self.directChildren.append(Weak(value: child))
        // Tell all children (including the new one) about the new total unit count.
        await updateUnitCountsOnChildren()
        return child
    }

    func addSource(withLabel label: String, unitCount: UInt64) async -> OWSProgressSource {
        self.totalDirectChildUnitCount += unitCount
        let source = OWSProgressSourceNode(
            label: label,
            parentLabels: self.labels,
            totalUnitCount: unitCount,
            parent: self,
            rootNode: rootNode
        )
        self.directChildren.append(Weak(value: source))
        // Tell all children (including the new one) about the new total unit count.
        await updateUnitCountsOnChildren()
        // All sources at all levels talk to the root to issue observer updates.
        await rootNode.addSource(source)
        source.emitProgressIfNeeded()
        return source
    }

    /// See ``OWSProgressChildNode/updateCompletedUnitCountMultiplier``.
    func updateCompletedUnitCountMultiplier(_ newValue: Float) async {
        self.completedUnitCountMultiplier = newValue
        // Recursively update children all the way down the tree.
        await updateUnitCountsOnChildren()
    }

    func updateUnitCountsOnChildren() async {
        // See `updateCompletedUnitCountMultiplier`.
        let childCompletedUnitCountMultiplier = self.completedUnitCountMultiplier
            * Float(totalUnitCount) / Float(totalDirectChildUnitCount)
        for child in directChildren {
            await child.value?.updateCompletedUnitCountMultiplier(
                childCompletedUnitCountMultiplier
            )
        }
    }
}

private class OWSProgressSourceNode: OWSProgressSource, OWSProgressChildNode {

    /// The chain of labels starting at the root (no label) and ending in this node's label.
    fileprivate let labels: [String]
    var completedUnitCount: UInt64 = 0
    let totalUnitCount: UInt64

    var sourceProgress: OWSProgress.SourceProgress {
        return OWSProgress.SourceProgress(
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            labels: labels
        )
    }

    /// See ``OWSProgressChildNode/updateCompletedUnitCountMultiplier``.
    /// This gets set immediately after initialization before it can possibly be read.
    fileprivate var completedUnitCountMultiplier: Float = 1

    /// Children hold strong referenced to their parents; as long as callers
    /// hold a reference to some child source (to increment its progress)
    /// the whole tree above that child will be retained.
    private let parent: OWSProgressSink
    /// Every node in the tree holds a strong reference to the root (and in turn its observer block).
    /// The root holds only weak references to its children.
    private let rootNode: OWSProgressRootNode

    init(
        label: String,
        parentLabels: [String],
        totalUnitCount: UInt64,
        parent: OWSProgressSink,
        rootNode: OWSProgressRootNode
    ) {
        self.labels = parentLabels + [label]
        self.totalUnitCount = totalUnitCount
        self.parent = parent
        self.rootNode = rootNode
    }

    func incrementCompletedUnitCount(by increment: UInt64) {
        let incrementedUnitCount: UInt64 = {
            if UInt64.max - increment < completedUnitCount {
                // Avoid UInt64 overflow, if necessary.
                return .max
            }

            return completedUnitCount + increment
        }()

        completedUnitCount = min(
            totalUnitCount,
            incrementedUnitCount
        )
        emitProgressIfNeeded()
    }

    /// Tracks whether an async progress update task has been scheduled
    /// but not run yet; if true further calls to ``emitProgressIfNeeded``
    /// will early exit.
    private var dirtyBit = false

    fileprivate func emitProgressIfNeeded() {
        guard !dirtyBit else {
            return
        }
        dirtyBit = true
        // Retain self, so that if the caller updates progress
        // to 100% then discards the reference to self, its
        // still retained long enough to update observers.
        Task { [self, rootNode] in
            // It looks risky to write this value from an
            // arbitrary task thread; but because we read
            // the progress value after setting this it should
            // never result in missed updates (just additional
            // unecessary updates).
            self.dirtyBit = false
            await rootNode.progressDidUpdate()
        }
    }

    /// See ``OWSProgressChildNode/updateCompletedUnitCountMultiplier``.
    func updateCompletedUnitCountMultiplier(_ newValue: Float) {
        self.completedUnitCountMultiplier = newValue
    }
}

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
/// First, call ``OWSProgress/createSink()`` to get a stream (or with an observer block) which is called with progress updates.
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
/// Labels _should be unique_ within the scope of the direct children of a given parent. Repeating labels
/// at the same level of the tree will replace the existing source/sink.
///
/// Using a unitCount of 0 is allowed, but potentially dangerous. An OWSProgress can only
/// reach 100% complete _once_. If you add a child or source with a unitCount of 0, it will
/// complete instantly. If it is the only child, it will complete its parent instantly, too. That
/// can potentially complete the root, which completes the whole progress and silences future updates.
///
/// A note on ``Foundation/NSProgress``.
/// This type _looks_ like NSProgress but behaves very differently.
/// * NSProgress is a class class meant to be updated and observed with KVO.
/// OWSProgress is a snapshot-in-time struct;OWSProgressSink manages observation.
/// * NSProgress uses locks for updates, making rapid updates on a single thread expensive.
/// OWSProgress optimizes for single-threaded updates; batching observer updates to do so efficiently.
/// * NSProgress requires you to know unit counts for all children up-front and they must all share units.
/// OWSProgress lets you add children lazily and renormalizes disparate units at each level of the tree.
public struct OWSProgress: Equatable, SomeOWSProgress, CustomStringConvertible {
    public struct ChildProgress: Equatable, SomeOWSProgress {
        /// The completed unit count of this particular source/sink.
        /// The units DO NOT necessarily correspond to the units of the root OWSProgress.
        public let completedUnitCount: UInt64
        /// The total unit count of this particular source/sink.
        /// The units DO NOT necessarily correspond to the units of the root OWSProgress.
        public let totalUnitCount: UInt64

        public let label: String
        // Nil if the parent is the root
        public let parentLabel: String?

        public init(
            completedUnitCount: UInt64,
            totalUnitCount: UInt64,
            label: String,
            parentLabel: String?,
        ) {
            self.completedUnitCount = completedUnitCount
            self.totalUnitCount = totalUnitCount
            self.label = label
            self.parentLabel = parentLabel
        }

        public var percentComplete: Float {
            roundProgressPercent(completedUnitCount: completedUnitCount, totalUnitCount: totalUnitCount)
        }

        public var isFinished: Bool {
            return totalUnitCount == completedUnitCount
        }

        public static func ==(lhs: OWSProgress.ChildProgress, rhs: OWSProgress.ChildProgress) -> Bool {
            return lhs.completedUnitCount == rhs.completedUnitCount
                && lhs.totalUnitCount == rhs.totalUnitCount
                && lhs.label == rhs.label
        }
    }

    /// The completed unit count across all direct children.
    public let completedUnitCount: UInt64
    /// The total unit count of all direct children.
    public let totalUnitCount: UInt64

    public init(
        completedUnitCount: UInt64,
        totalUnitCount: UInt64,
    ) {
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self._descendantProgresses = [:]
    }

#if DEBUG

    public static func withChildProgressForTesting(_ childProgress: ChildProgress) -> OWSProgress {
        return OWSProgress(
            completedUnitCount: 0,
            totalUnitCount: 1,
            descendantProgresses: [
                childProgress.label: [.root().appending(childLabel: childProgress.label): childProgress],
            ],
        )
    }

#endif

    fileprivate init(
        completedUnitCount: UInt64,
        totalUnitCount: UInt64,
        descendantProgresses: [String: [OWSProgressRootNode.Identifier: ChildProgress]],
    ) {
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self._descendantProgresses = descendantProgresses
    }

    public var description: String {
        "OWSProgress: \(completedUnitCount)/\(totalUnitCount), \(percentComplete * 100)%"
    }

    public var percentComplete: Float {
        if totalUnitCount > 0 {
            return roundProgressPercent(
                completedUnitCount: completedUnitCount,
                totalUnitCount: totalUnitCount,
            )
        } else if _descendantProgresses.isEmpty {
            // With no children, don't count as complete.
            return 0
        } else {
            // We have >1 children, but the count is 0, so the
            // children must have a total count of 0.
            // Complete instantly.
            return 1
        }
    }

    public var isFinished: Bool {
        if totalUnitCount > 0 {
            return totalUnitCount == completedUnitCount
        } else if _descendantProgresses.isEmpty {
            // With no children, don't count as complete.
            return false
        } else {
            // We have >1 children, but the count is 0, so the
            // children must have a total count of 0.
            // Complete instantly.
            return true
        }
    }

    private let _descendantProgresses: [String: [OWSProgressRootNode.Identifier: ChildProgress]]

    /// Get the latest progresses for all descendants with a given label.
    public func descendantProgresses(withLabel label: String) -> some Collection<ChildProgress> {
        return _descendantProgresses[label, default: [:]].values
    }

#if DEBUG
    public static func forPreview(_ percentComplete: Float) -> OWSProgress {
        return OWSProgress(completedUnitCount: UInt64(percentComplete * 100), totalUnitCount: 100)
    }
#endif

    public static var zero: OWSProgress {
        return OWSProgress(completedUnitCount: 0, totalUnitCount: 0)
    }

    /// Create a root sink, taking the single observer block of progress updates.
    /// See class docs for this type for usage.
    public static func createSink(_ observer: @escaping (OWSProgress) async -> Void) -> OWSProgressSink {
        let (sink, stream) = Self.createSink()
        Task {
            for await progress in stream {
                await observer(progress)
            }
        }
        return sink
    }

    /// Like ``createSink(_:)``, but instead of using an observer block to emit progress values, wraps callbacks in an AsyncStream.
    public static func createSink() -> (OWSProgressSink, AsyncStream<OWSProgress>) {
        var streamContinuation: AsyncStream<OWSProgress>.Continuation!
        let stream = AsyncStream<OWSProgress> { continuation in
            streamContinuation = continuation
        }
        let sink = OWSProgressRootNode(streamContinuation: streamContinuation)
        return (sink, stream)
    }

    public static func ==(lhs: OWSProgress, rhs: OWSProgress) -> Bool {
        // TODO: Why is descendantProgress omitted here?
        return lhs.completedUnitCount == rhs.completedUnitCount
            && lhs.totalUnitCount == rhs.totalUnitCount
    }
}

public protocol SomeOWSProgress {
    var completedUnitCount: UInt64 { get }
    var totalUnitCount: UInt64 { get }
    /// Percentage completion measured as (completedUnitCount / totalUnitCount)
    /// 0 if no children or sources have been added.
    var percentComplete: Float { get }
    /// Percent == 1. False if no children or sources have been added.
    var isFinished: Bool { get }
}

extension SomeOWSProgress {

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
}

/// Sinks are thread-safe and can have children added from any thread context.
public protocol OWSProgressSink {
    /// Add a child sink, returning it.
    /// Child sinks contribute to the total unit count of their parent.
    /// A child sink's progress is its own unit count weighted by the completed unit count across all its children.
    ///
    /// Using a unitCount of 0 is allowed, but potentially dangerous. An OWSProgress can only
    /// reach 100% complete _once_. If you add a child or source with a unitCount of 0, it will
    /// complete instantly. If it is the only child, it will complete its parent instantly, too. That
    /// can potentially complete the root, which completes the whole progress and silences future updates.
    ///
    /// **WARNING** adding a child to a parent sink after some sibling has previously updated progress
    /// results in undefined behavior; old progress values are not renormalized to new total unit counts.
    /// Adding grandchildren is allowed; typically you want to "reserve" proportional unit counts
    /// by adding a child up-front and then adding a grandchild to that child later.
    func addChild(withLabel label: String, unitCount: UInt64) async -> OWSProgressSink

    /// Add a source, returning it.
    /// Sources contribute to the total unit count of their parent.
    /// Sources are **NOT** thread-safe and should only be updated from a single thread or locking context.
    ///
    /// Using a unitCount of 0 is allowed, but potentially dangerous. An OWSProgress can only
    /// reach 100% complete _once_. If you add a child or source with a unitCount of 0, it will
    /// complete instantly. If it is the only child, it will complete its parent instantly, too. That
    /// can potentially complete the root, which completes the whole progress and silences future updates.
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

    func asProgressBlock() -> OWSURLSession.ProgressBlock {
        return { completedByteCount, totalByteCount in
            if self.completedUnitCount < completedByteCount {
                self.incrementCompletedUnitCount(by: UInt64(completedByteCount) - self.completedUnitCount)
            }
        }
    }

    /// Given some block of asynchronous work, update progress
    /// on the current source periodically (every ``timeInterval`` seconds)
    /// until the work block completes.
    /// Returns with the result of the work block when it completes.
    public func updatePeriodically<T, E>(
        timeInterval: TimeInterval = 0.1,
        estimatedTimeToCompletion: TimeInterval,
        work: () async throws(E) -> T,
    ) async throws(E) -> T {
        let startTime = CACurrentMediaTime()

        let updateTask = Task { [completedUnitCount, totalUnitCount] in
            var oldValue: UInt64 = 0
            // Minus one so the timer can never complete it.
            let maxValue = totalUnitCount - completedUnitCount - 1
            let unitsPerSecond = Double(totalUnitCount - completedUnitCount) / estimatedTimeToCompletion
            while oldValue < maxValue {
                try await Task.sleep(nanoseconds: timeInterval.clampedNanoseconds)
                var newValue = UInt64(clamping: (CACurrentMediaTime() - startTime) * unitsPerSecond)
                newValue = min(maxValue, newValue)
                let delta = newValue - oldValue
                oldValue = newValue
                if delta > 0 {
                    incrementCompletedUnitCount(by: delta)
                }
            }
        }

        do throws(E) {
            let result = try await work()
            updateTask.cancel()
            // Don't call incrementCompletedUnitCount concurrently with updateTask.
            try? await updateTask.value
            incrementCompletedUnitCount(by: totalUnitCount)
            return result
        } catch {
            updateTask.cancel()
            try? await updateTask.value
            throw error
        }
    }
}

// MARK: - Root Node

/// Root node for OWSProgress. Does not itself have a unit count or concept of progress;
/// its children define units entirely.
private actor OWSProgressRootNode: OWSProgressSink {

    private let streamContinuation: AsyncStream<OWSProgress>.Continuation
    private var observerQueue = SerialTaskQueue()

    // Maps from node label to a weak reference to the node
    // for all nodes at all layers of the tree.
    private var allDescendantNodes = [Identifier: Weak<OWSProgressChildNode>]()

    /// A label is not enough to identify a child; we identify by the sequence
    /// of labels starting at the root.
    struct Identifier: Hashable, Equatable {
        /// An empty chain represents the root.
        let chain: [String]

        private init(chain: [String]) {
            self.chain = chain
        }

        var label: String? { chain.last }

        static func root() -> Self {
            return Self(chain: [])
        }

        func appending(childLabel: String) -> Identifier {
            return Identifier(chain: chain + [childLabel])
        }

        func parent() -> Identifier? {
            if chain.isEmpty {
                return nil
            } else {
                return Identifier(chain: chain.dropLast())
            }
        }
    }

    // Maps from parent identifier to labels of direct children.
    private var childLabels = [Identifier: Set<String>]()

    // Maps from parent label to the sum of unit counts of direct
    // children. We cache this since it doesn't change often and
    // saves the O(n) time spent adding on every progress update.
    private var totalUnitCountOfChildren = [Identifier: UInt64]()
    // Maps from parent label to the sum of unit counts of direct
    // children. We cache this since it doesn't change often and
    // saves the O(n) time spent adding on every progress update.
    private var completedUnitCountOfChildren = [Identifier: UInt64]()
    // Maps from node label to the last computed unit counts
    // of nodes with that label, in its parent's units.
    private var childProgresses = [String: [Identifier: OWSProgress.ChildProgress]]()

    // We cache these values so that we can compute diffs efficiently.
    private var totalUnitCountOfDirectChildren: UInt64 = 0
    private var completedUnitCountOfDirectChildren: UInt64 = 0

    fileprivate init(streamContinuation: AsyncStream<OWSProgress>.Continuation) {
        self.streamContinuation = streamContinuation
    }

    func addChild(withLabel label: String, unitCount: UInt64) async -> OWSProgressSink {
        let child = OWSProgressSinkNode(
            label: label,
            parent: self,
            rootNode: self,
        )
        self.addChild(child, toParent: .root(), unitCount: unitCount)
        return child
    }

    func addSource(withLabel label: String, unitCount: UInt64) async -> OWSProgressSource {
        let child = OWSProgressSourceNode(
            label: label,
            totalUnitCount: unitCount,
            parent: self,
            rootNode: self,
        )
        self.addChild(child, toParent: .root(), unitCount: unitCount)
        return child
    }

    fileprivate func progressDidUpdate(updatedNode: OWSProgressSourceNode) {
        if updatedNode.isOrphaned {
            // If the node was orphaned (replaced by another node
            // created with the same label), stop. Updates from
            // orphan labels are ignored.
            return
        }

        self.recursiveUpdateCompletedUnitCounts(
            forNodeWithIdentifier: updatedNode.identifier,
            newCompletedUnitCount: updatedNode.completedUnitCount,
        )

        let progress = OWSProgress(
            completedUnitCount: self.completedUnitCountOfDirectChildren,
            totalUnitCount: self.totalUnitCountOfDirectChildren,
            descendantProgresses: self.childProgresses,
        )
        observerQueue.enqueue { [streamContinuation, progress] in
            streamContinuation.yield(progress)
            if progress.isFinished {
                streamContinuation.finish()
            }
        }
    }

    // MARK: - Child Updates

    fileprivate func addChild(
        _ child: OWSProgressChildNode,
        toParent parentIdentifier: Identifier,
        unitCount: UInt64,
    ) {
        let label = child.label
        let identifier = child.identifier

        if allDescendantNodes[parentIdentifier]?.value?.isOrphaned == true {
            // If the parent was orphaned (replaced by another node
            // created with the same label), stop. The new node will
            // point nowhere and be ignored.
            return
        }

        if allDescendantNodes[identifier] != nil {
            // Remove any existing children first.
            self.removeChild(withIdentifier: identifier)
        }

        // First, add the node to its parent's child references.
        self.allDescendantNodes[identifier] = Weak(value: child)
        self.childLabels[parentIdentifier, default: Set()].insert(label)
        if child is OWSProgressParentNode {
            self.totalUnitCountOfChildren[identifier] = 0
            self.completedUnitCountOfChildren[identifier] = 0
        }
        self.childProgresses[label, default: [:]][identifier] = OWSProgress.ChildProgress(
            completedUnitCount: 0,
            totalUnitCount: unitCount,
            label: label,
            parentLabel: parentIdentifier.label,
        )

        // Update the parent's counts
        if parentIdentifier == .root() {
            self.totalUnitCountOfDirectChildren += unitCount
        } else {
            var totalUnitCountOfChildren = self.totalUnitCountOfChildren[parentIdentifier]!
            totalUnitCountOfChildren += unitCount
            self.totalUnitCountOfChildren[parentIdentifier] = totalUnitCountOfChildren

            // Update the progress of the parent.
            let oldParentProgress = childProgresses[parentIdentifier.label!]![parentIdentifier]!
            // The _parent's_ total unit count is unchanged.
            let newParentTotalUnitCount = oldParentProgress.totalUnitCount
            // The parent's completed unit count changes proportionally.
            let newParentCompletedUnitCount: UInt64
            if totalUnitCountOfChildren == 0 {
                newParentCompletedUnitCount = newParentTotalUnitCount
            } else {
                newParentCompletedUnitCount = renormalizeCompletedUnitCount(
                    childrensCompletedUnitCount: completedUnitCountOfChildren[parentIdentifier]!,
                    childrensTotalUnitCount: totalUnitCountOfChildren,
                    parentTotalUnitCount: newParentTotalUnitCount,
                )
            }

            // Now update the progress values all the way up the tree.
            self.recursiveUpdateCompletedUnitCounts(
                forNodeWithIdentifier: parentIdentifier,
                newCompletedUnitCount: newParentCompletedUnitCount,
            )
        }

        // Lastly recompute and emit progress
        let progress = OWSProgress(
            completedUnitCount: completedUnitCountOfDirectChildren,
            totalUnitCount: totalUnitCountOfDirectChildren,
            descendantProgresses: childProgresses,
        )
        observerQueue.enqueue { [streamContinuation, progress] in
            streamContinuation.yield(progress)
            if progress.isFinished {
                streamContinuation.finish()
            }
        }
    }

    fileprivate func removeChild(withIdentifier identifier: Identifier) {
        guard let label = identifier.label else {
            owsFailDebug("can't remove root")
            return
        }

        // Mark the child and its children orphaned; future updates to it
        // will be ignored.
        var identifiersToMarkOrphaned = Set(arrayLiteral: identifier)
        while let identifierToMarkOrphaned = identifiersToMarkOrphaned.popFirst() {
            let childLabels = self.childLabels[identifierToMarkOrphaned] ?? Set()
            identifiersToMarkOrphaned.formUnion(childLabels.map({ identifierToMarkOrphaned.appending(childLabel: $0) }))
            allDescendantNodes[identifierToMarkOrphaned]?.value?.isOrphaned = true
        }

        // Mark all its children

        guard
            let parentIdentifier = identifier.parent(),
            let removedNodeProgress = self.childProgresses[label]?[identifier]
        else {
            owsFailDebug("Removing a label that didn't exist?")
            return
        }

        // First, remove the node from its parent's child references.
        self.childLabels[parentIdentifier]?.remove(label)

        // Next, update the progress on the parent.
        if parentIdentifier == .root() {
            self.totalUnitCountOfDirectChildren -= removedNodeProgress.totalUnitCount
            self.completedUnitCountOfDirectChildren -= removedNodeProgress.completedUnitCount
        } else {
            // The direct parent's update is special; we've affected the total
            // unit count of its children as well as the completed unit count
            // of its children. This does NOT affect the total unit count
            // in _its_ parent, so once we compute the direct parent's new
            // completed unit count we can update recursively up the tree as normal.
            var totalUnitCountOfChildren = self.totalUnitCountOfChildren[parentIdentifier]!
            totalUnitCountOfChildren -= removedNodeProgress.totalUnitCount
            self.totalUnitCountOfChildren[parentIdentifier] = totalUnitCountOfChildren
            var completedUnitCountOfChildren = self.completedUnitCountOfChildren[parentIdentifier]!
            completedUnitCountOfChildren -= removedNodeProgress.completedUnitCount
            self.completedUnitCountOfChildren[parentIdentifier] = completedUnitCountOfChildren

            // Update the progress of the parent.
            let oldParentProgress = childProgresses[parentIdentifier.label!]![parentIdentifier]!
            // The _parent's_ total unit count is unchanged.
            let newParentTotalUnitCount = oldParentProgress.totalUnitCount
            // The parent's completed unit count changes proportionally.
            let newParentCompletedUnitCount: UInt64
            if totalUnitCountOfChildren == 0 {
                newParentCompletedUnitCount = newParentTotalUnitCount
            } else {
                newParentCompletedUnitCount = renormalizeCompletedUnitCount(
                    childrensCompletedUnitCount: completedUnitCountOfChildren,
                    childrensTotalUnitCount: totalUnitCountOfChildren,
                    parentTotalUnitCount: newParentTotalUnitCount,
                )
            }

            // Now update the progress values all the way up the tree.
            self.recursiveUpdateCompletedUnitCounts(
                forNodeWithIdentifier: parentIdentifier,
                newCompletedUnitCount: newParentCompletedUnitCount,
            )
        }

        // Last, remove it and all its children from our references.
        var identifiersToRemove = Set<Identifier>(arrayLiteral: identifier)
        while let identifierToRemove = identifiersToRemove.popFirst() {
            let childLabels = self.childLabels.removeValue(forKey: identifierToRemove) ?? Set()
            identifiersToRemove.formUnion(childLabels.map({ identifierToRemove.appending(childLabel: $0) }))
            self.allDescendantNodes.removeValue(forKey: identifierToRemove)
            self.totalUnitCountOfChildren.removeValue(forKey: identifierToRemove)
            self.completedUnitCountOfChildren.removeValue(forKey: identifierToRemove)
            self.childProgresses[identifierToRemove.label!]?.removeValue(forKey: identifierToRemove)
        }
    }

    private func recursiveUpdateCompletedUnitCounts(
        forNodeWithIdentifier identifier: Identifier,
        newCompletedUnitCount: UInt64,
    ) {
        let label = identifier.label!
        let oldChildProgress = self.childProgresses[label]![identifier]!
        let newChildProgress = OWSProgress.ChildProgress(
            completedUnitCount: newCompletedUnitCount,
            totalUnitCount: oldChildProgress.totalUnitCount,
            label: label,
            parentLabel: identifier.parent()?.label,
        )
        self.childProgresses[label]![identifier] = newChildProgress

        let parentIdentifier = identifier.parent()!
        if parentIdentifier == .root() {
            self.completedUnitCountOfDirectChildren -= oldChildProgress.completedUnitCount
            self.completedUnitCountOfDirectChildren += newChildProgress.completedUnitCount
            // Done.
        } else {
            // Update progress on the parent and then call recursively
            var completedUnitCountOfChildren = self.completedUnitCountOfChildren[parentIdentifier]!
            completedUnitCountOfChildren -= oldChildProgress.completedUnitCount
            completedUnitCountOfChildren += newChildProgress.completedUnitCount
            self.completedUnitCountOfChildren[parentIdentifier] = completedUnitCountOfChildren

            let totalUnitCountOfChildren = self.totalUnitCountOfChildren[parentIdentifier]!
            let totalUnitCount = self.childProgresses[parentIdentifier.label!]![parentIdentifier]!.totalUnitCount
            let newParentCompletedUnitCount = renormalizeCompletedUnitCount(
                childrensCompletedUnitCount: completedUnitCountOfChildren,
                childrensTotalUnitCount: totalUnitCountOfChildren,
                parentTotalUnitCount: totalUnitCount,
            )
            return self.recursiveUpdateCompletedUnitCounts(
                forNodeWithIdentifier: parentIdentifier,
                newCompletedUnitCount: newParentCompletedUnitCount,
            )
        }
    }
}

// MARK: - Private protocols

private protocol OWSProgressNode {}

private protocol OWSProgressParentNode: OWSProgressNode {
    var identifier: OWSProgressRootNode.Identifier { get }
}

private protocol OWSProgressChildNode: OWSProgressNode {
    var label: String { get }
    var identifier: OWSProgressRootNode.Identifier { get }
    var parent: OWSProgressParentNode { get }
    /// Should only be read from root node's isolation context.
    var isOrphaned: Bool { get set }
}

extension OWSProgressRootNode: OWSProgressParentNode {
    nonisolated var identifier: Identifier { .root() }
}

// MARK: - Node implementations

/// A sink that is itself a child to another sink.
private class OWSProgressSinkNode: OWSProgressSink, OWSProgressParentNode, OWSProgressChildNode {

    var isOrphaned: Bool = false

    var label: String
    var identifier: OWSProgressRootNode.Identifier

    let parent: OWSProgressParentNode
    let rootNode: OWSProgressRootNode

    init(
        label: String,
        parent: OWSProgressParentNode,
        rootNode: OWSProgressRootNode,
    ) {
        self.label = label
        self.parent = parent
        self.rootNode = rootNode
        self.identifier = parent.identifier.appending(childLabel: label)
    }

    func addChild(withLabel label: String, unitCount: UInt64) async -> OWSProgressSink {
        let child = OWSProgressSinkNode(
            label: label,
            parent: self,
            rootNode: rootNode,
        )
        // Call up to the parent to utilize its isolation context
        await rootNode.addChild(child, toParent: self.identifier, unitCount: unitCount)
        return child
    }

    func addSource(withLabel label: String, unitCount: UInt64) async -> OWSProgressSource {
        let child = OWSProgressSourceNode(
            label: label,
            totalUnitCount: unitCount,
            parent: self,
            rootNode: rootNode,
        )
        // Call up to the parent to utilize its isolation context
        await rootNode.addChild(child, toParent: self.identifier, unitCount: unitCount)
        return child
    }
}

private class OWSProgressSourceNode: OWSProgressSource, OWSProgressChildNode {

    var isOrphaned: Bool = false
    var label: String
    var identifier: OWSProgressRootNode.Identifier

    let totalUnitCount: UInt64
    var completedUnitCount: UInt64

    let parent: OWSProgressParentNode
    let rootNode: OWSProgressRootNode

    init(
        label: String,
        totalUnitCount: UInt64,
        parent: OWSProgressParentNode,
        rootNode: OWSProgressRootNode,
    ) {
        self.label = label
        self.parent = parent
        self.rootNode = rootNode
        self.totalUnitCount = totalUnitCount
        self.completedUnitCount = 0
        self.identifier = parent.identifier.appending(childLabel: label)
    }

    func incrementCompletedUnitCount(by increment: UInt64) {
        var increment = increment
        increment = min(increment, totalUnitCount - completedUnitCount)
        if increment == 0 {
            return
        }
        completedUnitCount += increment
        emitProgressIfNeeded()
    }

    /// Tracks whether an async progress update task has been scheduled
    /// but not run yet; if true further calls to ``emitProgressIfNeeded``
    /// will early exit.
    private let dirtyBit = AtomicBool(false, lock: .init())

    fileprivate func emitProgressIfNeeded() {
        guard dirtyBit.tryToSetFlag() else {
            return
        }
        // Retain self, so that if the caller updates progress to 100% then
        // discards the reference to self, it's still retained long enough to
        // update observers.
        Task { [self, rootNode] in
            // It looks risky to write this value from an arbitrary task thread; but
            // because we read the progress value after setting this it should never
            // result in missed updates (just additional unecessary updates).
            self.dirtyBit.set(false)
            await rootNode.progressDidUpdate(updatedNode: self)
        }
    }
}

private func roundProgressPercent(
    completedUnitCount: UInt64,
    totalUnitCount: UInt64,
) -> Float {
    if totalUnitCount == 0 {
        // The unit count assigned to the node is 0 so it
        // is instantly complete.
        return 1
    }
    if completedUnitCount >= totalUnitCount {
        return 1
    }
    let rawPercent = Float(completedUnitCount) / Float(totalUnitCount)
    if rawPercent >= 0.99 {
        // Never round 99% and above to 100%. Cap at 0.99.
        return 0.99
    }
    return rawPercent
}

private func renormalizeCompletedUnitCount(
    childrensCompletedUnitCount: UInt64,
    childrensTotalUnitCount: UInt64,
    parentTotalUnitCount: UInt64,
) -> UInt64 {
    if parentTotalUnitCount == 0 {
        return 0
    }
    if childrensCompletedUnitCount >= childrensTotalUnitCount {
        return parentTotalUnitCount
    }
    let rawPercent = Double(childrensCompletedUnitCount) / Double(childrensTotalUnitCount)
    let rawUnitCount = UInt64(ceil(Double(parentTotalUnitCount) * rawPercent))
    if rawUnitCount == parentTotalUnitCount {
        // Never round up to 100%; 100% is caught by the >= check above
        // and the most we should return is 99%.
        return rawUnitCount - 1
    } else {
        return rawUnitCount
    }
}

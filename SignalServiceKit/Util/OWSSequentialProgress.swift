//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// An Enum representing sequential progress steps.
/// Each step represents one direct child of the root node, with the iterable cases in the order they are executed.
public protocol OWSSequentialProgressStep: RawRepresentable<String>, Hashable, CaseIterable {
    /// How many units of progress this step represents.
    ///
    /// It makes things easier to think about if all the enum values add to 100,
    /// because then each number is just the % allocated to each step, but the
    /// math works regardless of what the counts add up to.
    var progressUnitCount: UInt64 { get }
}

/// A thin wrapper around OWSProgress that provides convenience methods to extract
/// progress values when the caller can assume all steps happen sequentially, with the
/// next one starting only after the previous one finishes, and represents those steps as
/// an enum with the iterable cases in the order they are executed.
public struct OWSSequentialProgress<StepEnum>: Equatable, SomeOWSProgress where StepEnum: OWSSequentialProgressStep {
    public let progress: OWSProgress

    /// The completed unit count across all direct children.
    public var completedUnitCount: UInt64 { progress.completedUnitCount }
    /// The total unit count of all direct children.
    public var totalUnitCount: UInt64 { progress.totalUnitCount }

    /// Get the latest progress for any source/sink at any layer of the progress tree.
    /// Maps from source/child sink label to the progress of that node.
    /// Note: if there are multiple children with the same label, will pick an
    /// arbitrary child. In most cases, there will be just one child and this
    /// is fine and this API is provided for simplicity.
    /// If not, use `progressesForAllChildren` to get the full acounting
    /// of duplicate labels.
    public func progressForChild(label: String) -> OWSProgress.ChildProgress? {
        return progress.progressForChild(label: label)
    }

    /// Get the latest progress for any source/sink at any layer of the progress tree.
    /// Maps from source/child sink label to the progress of all nodes with that label.
    public func progressesForAllChildren(withLabel label: String) -> [OWSProgress.ChildProgress] {
        return progress.progressesForAllChildren(withLabel: label)
    }

    public var percentComplete: Float { return progress.percentComplete }

    public var isFinished: Bool { return progress.isFinished }

    fileprivate init(progress: OWSProgress) {
        self.progress = progress
    }

    public func progress(for step: StepEnum) -> OWSProgress.ChildProgress? {
        return self.progressesForAllChildren(withLabel: step.rawValue)
            .first(where: { $0.parentLabel == nil })
    }

    public var currentStep: StepEnum {
        for step in StepEnum.allCases {
            guard let stepProgress = progress(for: step) else {
                // If we don't have a child progress for a given step, skip it.
                continue
            }

            guard stepProgress.percentComplete < 1 else {
                // If we've completed a step, skip it.
                continue
            }

            return step
        }

        return Array(StepEnum.allCases).last!
    }

    public var currentStepProgress: OWSProgress.ChildProgress? {
        return progress(for: currentStep)
    }

    /// Create a root sink, taking the single observer block of progress updates.
    /// See class docs of ``OWSProgress`` for usage.
    public static func createSink(
        _ observer: @escaping (OWSSequentialProgress<StepEnum>) async -> Void,
    ) async -> OWSSequentialProgressRootSink<StepEnum> {
        let sink = OWSProgress.createSink { progress in
            await observer(progress.sequential(StepEnum.self))
        }
        return await OWSSequentialProgressRootSink(sink: sink)
    }

    /// Like ``createSink(_:)``, but instead of using an observer block to emit progress values, emits using a returned AsyncStream.
    public static func createSink() async -> (OWSSequentialProgressRootSink<StepEnum>, AsyncStream<OWSSequentialProgress<StepEnum>>) {
        var stepStreamContinuation: AsyncStream<OWSSequentialProgress<StepEnum>>.Continuation!
        let stepStream = AsyncStream<OWSSequentialProgress<StepEnum>> { continuation in
            stepStreamContinuation = continuation
        }
        let (sink, stream) = OWSProgress.createSink()
        Task {
            for await progress in stream {
                stepStreamContinuation.yield(progress.sequential(StepEnum.self))
            }
            stepStreamContinuation.finish()
        }
        return await (OWSSequentialProgressRootSink(sink: sink), stepStream)
    }
}

/// Wrapper around the root sink for an OWSSequentialProgress emitting OWSProgress.
/// The root always has one child per StepEnum step; it cannot have more or fewer children.
public struct OWSSequentialProgressRootSink<StepEnum: OWSSequentialProgressStep> {

    private let sink: OWSProgressSink

    private let children: [StepEnum: OWSProgressSink]

    fileprivate init(sink: OWSProgressSink) async {
        self.sink = sink
        var children = [StepEnum: OWSProgressSink]()
        for step in StepEnum.allCases {
            children[step] = await sink.addChild(withLabel: step.rawValue, unitCount: step.progressUnitCount)
        }
        self.children = children
    }

    public func child(for step: StepEnum) -> OWSProgressSink {
        return children[step]!
    }
}

extension OWSProgress {

    public func sequential<StepEnum>(
        _ stepEnum: StepEnum.Type,
    ) -> OWSSequentialProgress<StepEnum> where StepEnum: CaseIterable, StepEnum: RawRepresentable<String> {
        return .init(progress: self)
    }
}

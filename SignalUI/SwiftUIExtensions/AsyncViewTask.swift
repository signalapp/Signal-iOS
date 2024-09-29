//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI

// MARK: - AsyncViewTask

/// Represents an async operation that can be associated with the lifetime of
/// a view using the `task(_:)` view modifier.
public protocol AsyncViewTask: Identifiable {
    /// Optionally provide a custom priority for the task. By default, the task
    /// will be executed with the `.userInitied` priority.
    /// See the `task(id:priority:_:)` view modifier for more information.
    var priority: TaskPriority? { get }

    /// The asynchronous action performed by the task.
    func perform() async
}

extension AsyncViewTask {
    public var priority: TaskPriority? { nil }
}

// MARK: - AsyncViewTaskModifier

extension View {
    /// Associates a binding to an `AsyncViewTask` with the lifetime of a view.
    ///
    /// When the binding is `nil`, the task is not executing. To begin the task
    /// set the value of the binding to an instance of the `AsyncTask` type.
    ///
    /// Buttons and other controls are automatically disabled while the task is
    /// executing.
    ///
    /// To cancel the active task, set the value of the binding to `nil` or a
    /// new task value. The previous task will automatically be cancelled before
    /// a new task begins.
    ///
    /// ```swift
    /// struct Nap: AsyncViewTask {
    ///   let id = UUID()
    ///   var duration: ContinousClock.Duration
    ///
    ///   func perform() async {
    ///     try? await Task.sleep(for: duration)
    ///   }
    /// }
    ///
    /// struct NappingButton: View {
    ///   @State private var nap: Nap?
    ///
    ///   var body: some View {
    ///     Button("Take a Nap") {
    ///       nap = Nap(duration: .seconds(60))
    ///     }
    ///     .task($nap.animation())
    ///   }
    /// }
    /// ```
    public func task<AsyncTask: AsyncViewTask>(_ task: Binding<AsyncTask?>) -> some View {
        modifier(AsyncViewTaskModifier(task: task))
    }
}

public struct AsyncViewTaskModifier<Task: AsyncViewTask>: ViewModifier {
    @Binding var task: Task?

    public func body(content: Content) -> some View {
        content
            .disabled(task != nil)
            .task(id: task?.id, priority: task?.priority ?? .userInitiated) {
                guard let currentTask = task else { return }
                defer { task = nil }
                await currentTask.perform()
            }
    }
}

//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct ProgressReportingTask<T, E: Error> {

    public let task: Task<T, E>
    public let progress: Progress

    public init(task: Task<T, E>, progress: Progress) {
        self.task = task
        self.progress = progress
    }
}

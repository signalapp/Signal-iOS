//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

struct LimitedThrowingTaskGroup {
    var taskGroup: ThrowingTaskGroup<Void, Error>
    var remainingCapacity: Int

    mutating func addTask(operation: @escaping @Sendable () async throws -> Void) async throws {
        if remainingCapacity > 0 {
            remainingCapacity -= 1
        } else {
            // Once we've kicked off the maximum number of concurrent tasks, we always
            // wait for one to finish before starting the next one.
            try await taskGroup.next()
        }
        taskGroup.addTask(operation: operation)
    }
}

func withLimitedThrowingTaskGroup(limit: Int, body: (inout LimitedThrowingTaskGroup) async throws -> Void) async rethrows {
    try await withThrowingTaskGroup(of: Void.self) { taskGroup in
        var limitedTaskGroup = LimitedThrowingTaskGroup(taskGroup: taskGroup, remainingCapacity: limit)
        try await body(&limitedTaskGroup)
        try await taskGroup.waitForAll()
    }
}

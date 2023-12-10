//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// An Operation that can be used with Swift Concurrency.
///
/// There are two separate Swift Concurrency integrations:
///
/// (1) The caller passes a continuation and can therefore `await` the
/// result of this operation. The caller must add this Operation to an
/// OperationQueue.
///
/// (2) The block parameter is `async` and can call `async` functions.
///
/// Note that these integrations are independent: you could have an
/// `AwaitableBlockOperation` that runs its block synchronously, and you
/// could have an `AsyncBlockOperation` that runs an async block but doesn't
/// allow the caller to wait for it to finish.
final class AwaitableAsyncBlockOperation: OWSOperation {
    private let completionContinuation: CheckedContinuation<Void, Error>
    private let asyncBlock: () async throws -> Void

    init(completionContinuation: CheckedContinuation<Void, Error>, asyncBlock: @escaping () async throws -> Void) {
        self.completionContinuation = completionContinuation
        self.asyncBlock = asyncBlock
    }

    override func run() {
        Task {
            do {
                try await self.asyncBlock()
                self.reportSuccess()
            } catch {
                self.reportError(error)
            }
        }
    }

    override func didSucceed() {
        completionContinuation.resume(returning: ())
    }

    override func didFail(error: Error) {
        completionContinuation.resume(throwing: error)
    }
}

//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// This class can be used by ``SDSDatabaseStorage`` to learn of
/// database writes by other processes.
///
/// * `notifyChanged` should be called after every write
///   transaction completes.
/// * `callback` is invoked when a write from another process
///   is detected.
final class SDSCrossProcess: Sendable {

    private static let localPid = getpid()

    private let notifyToken: DarwinNotificationCenter.ObserverToken

    init(callback: @escaping @Sendable @MainActor () -> Void) {
        self.notifyToken = DarwinNotificationCenter.addObserver(name: .sdsCrossProcess, queue: .main) { token in
            let fromPid = DarwinNotificationCenter.getState(observer: token)
            let isLocal = fromPid == Self.localPid
            guard !isLocal else { return }
            // we told the addObserver call above to execute this block on the main thread so we should already be isolated
            // but there's no way to tell the compiler this with these old APIs, so we tell it to assume we are.
            MainActor.assumeIsolated {
                callback()
            }
        }
    }

    deinit {
        if DarwinNotificationCenter.isValid(notifyToken) {
            DarwinNotificationCenter.removeObserver(notifyToken)
        }
    }

    @MainActor
    func notifyChanged() {
        DarwinNotificationCenter.setState(UInt64(Self.localPid), observer: notifyToken)
        DarwinNotificationCenter.postNotification(name: .sdsCrossProcess)
    }
}

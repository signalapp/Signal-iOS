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

    private let notifyTokens: [DarwinNotificationCenter.ObserverToken]

    init(callback: @escaping @Sendable @MainActor () -> Void) {
        var notifyTokens: [DarwinNotificationCenter.ObserverToken] = []
        let block = { (_: DarwinNotificationCenter.ObserverToken) -> Void in
            // the addObserver calls below execute this block on the main thread so we should already be isolated
            // but there's no way to tell the compiler this with these old APIs, so we tell it to assume we are.
            MainActor.assumeIsolated {
                callback()
            }
        }

        // listen to everyone but our self; then when posting post our own type
        let currentAppContextType = CurrentAppContext().type
        for appContextType in AppContextType.allCases {
            if appContextType == currentAppContextType { continue }
            notifyTokens.append(DarwinNotificationCenter.addObserver(name: .sdsCrossProcess(for: appContextType), queue: .main, block: block))
        }
        self.notifyTokens = notifyTokens
    }

    deinit {
        for notifyToken in notifyTokens {
            if DarwinNotificationCenter.isValid(notifyToken) {
                DarwinNotificationCenter.removeObserver(notifyToken)
            }
        }
    }

    @MainActor
    func notifyChanged() {
        DarwinNotificationCenter.postNotification(name: .sdsCrossProcess(for: CurrentAppContext().type))
    }
}

//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

@Suite(.serialized)
struct ClockSkewManagerTest {
    private static let observedNames: [Notification.Name] = [
        .clockSkewDidChange,
        .clockSkewShouldBlockConnectionsDidChange,
        .clockSkewShouldBeRemeasured,
    ]

    private let notificationCenter: NotificationCenter
    private let now: Date

    private let manager: ClockSkewManager

    init() {
        let now = Date()
        self.notificationCenter = NotificationCenter()
        self.now = now

        self.manager = ClockSkewManager(
            dateProvider: { now },
            notificationCenter: notificationCenter,
        )
    }

    /// A server timestamp that leaves the device's clock `skew` ahead of the
    /// server's.
    private func serverTimestampMs(deviceAheadBy skew: TimeInterval) -> UInt64 {
        return now.addingTimeInterval(-skew).ows_millisecondsSince1970
    }

    /// Runs `trigger`, then returns the notifications it posted, in order.
    private func notifications(triggeredBy trigger: () -> Void) async -> [Notification.Name] {
        let recorded = AtomicValue([Notification.Name](), lock: .init())
        let observers = Self.observedNames.map { name in
            notificationCenter.addObserver(name: name) { _ in
                recorded.update { $0.append(name) }
            }
        }
        defer { observers.forEach { notificationCenter.removeObserver($0) } }

        trigger()

        // Notifications are posted asynchronously onto the main queue, so let
        // anything already enqueued run first.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        return recorded.get()
    }

    /// Report the given skew, waiting for any posted notifications.
    @discardableResult
    private func reportSkew(_ skew: TimeInterval) async -> [Notification.Name] {
        return await notifications {
            manager.serverDidReportTimestamp(serverTimestampMs(deviceAheadBy: skew))
        }
    }

    @Test(arguments: [
        (ClockSkewManager.maximumAllowedClockSkew + .hour, true),
        (-(ClockSkewManager.maximumAllowedClockSkew + .hour), true),
        (ClockSkewManager.maximumAllowedClockSkew - .hour, false),
        (-(ClockSkewManager.maximumAllowedClockSkew - .hour), false),
    ] as [(deviceAheadBy: TimeInterval, isSkewed: Bool)])
    func skewDetection(testCase: (deviceAheadBy: TimeInterval, isSkewed: Bool)) async {
        let recorded = await reportSkew(testCase.deviceAheadBy)

        #expect(manager.isClockSkewed == testCase.isSkewed)
        #expect(manager.shouldBlockConnections == testCase.isSkewed)
        if testCase.isSkewed {
            #expect(recorded == [.clockSkewDidChange, .clockSkewShouldBlockConnectionsDidChange])
        } else {
            #expect(recorded == [])
        }
    }

    /// When foregrounded while skewed we unblock connections to re-measure; if
    /// we find that we're still skewed, the whole time we should have had
    /// `isClockSkewed` stay `true`.
    @Test
    func stillSkewedReportPostsOnlyConnectionChange() async {
        await reportSkew(ClockSkewManager.maximumAllowedClockSkew + .hour)
        #expect(manager.isClockSkewed)
        #expect(manager.shouldBlockConnections)

        let whenActivated = await notifications {
            notificationCenter.post(name: .OWSApplicationDidBecomeActive, object: nil)
        }
        #expect(whenActivated == [.clockSkewShouldBlockConnectionsDidChange])
        #expect(manager.isClockSkewed)
        #expect(!manager.shouldBlockConnections)

        let whenStillSkewed = await reportSkew(ClockSkewManager.maximumAllowedClockSkew + (2 * .hour))
        #expect(whenStillSkewed == [.clockSkewShouldBlockConnectionsDidChange])
        #expect(manager.isClockSkewed)
        #expect(manager.shouldBlockConnections)
    }

    /// A clock change invalidates our last measurement even when it doesn't
    /// change any of our state, so it must always ask for a fresh one.
    @Test
    func clockChangeRemeasuresEvenWhenNothingElseChanges() async {
        let recorded = await notifications {
            notificationCenter.post(name: .NSSystemClockDidChange, object: nil)
        }

        #expect(recorded == [.clockSkewShouldBeRemeasured])
    }

    /// Connections need to cycle while they're still blocked; unblocking first
    /// would let them open, only to be immediately torn down.
    @Test
    func clockChangeRemeasuresBeforeUnblocking() async {
        await reportSkew(ClockSkewManager.maximumAllowedClockSkew + .hour)

        let recorded = await notifications {
            notificationCenter.post(name: .NSSystemClockDidChange, object: nil)
        }

        #expect(recorded == [.clockSkewShouldBeRemeasured, .clockSkewShouldBlockConnectionsDidChange])
        #expect(manager.isClockSkewed)
        #expect(!manager.shouldBlockConnections)
    }
}

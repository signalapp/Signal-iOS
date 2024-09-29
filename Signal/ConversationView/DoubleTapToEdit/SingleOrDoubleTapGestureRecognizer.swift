//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import UIKit

public protocol SingleOrDoubleTapGestureDelegate: AnyObject {

    /// A single tap was recognized; return true if handled to end the gesture immediately.
    func handleSingleTap(_ sender: SingleOrDoubleTapGestureRecognizer) -> Bool

    /// A double tap was recognized; return true if handled to signal to `didEndGesture`.
    func handleDoubleTap(_ sender: SingleOrDoubleTapGestureRecognizer) -> Bool

    /// The gesture ended in one of three ways:
    /// 1. `handleSingleTap` returned true
    /// 2. `handleDoubleTap` returned true OR false
    /// 3. `handleSingleTap` returned false, then the gesture timed out waiting for double tap.
    ///
    /// - parameter wasHandled: True if either `handleSingleTap` or `handleDoubleTap` returned true this gesture.
    func didEndGesture(_ sender: SingleOrDoubleTapGestureRecognizer, wasHandled: Bool) -> Void
}

public class SingleOrDoubleTapGestureRecognizer: UIGestureRecognizer {

    // MARK: - API

    public func setTapDelegate(_ delegate: SingleOrDoubleTapGestureDelegate) {
        self.tapDelegate = delegate
    }

    // MARK: - Private

    /// The default for UITapGestureRecognizer is 0.35. This is lower because of where we use it (conversation view)
    /// where we want to balance the speed of detecting a single tap with the window to actually do a double tap.
    /// Roughly, >=0.3 feels too slow when intending to single tap; below 0.2 makes it impossible to double tap.
    private static let maxIntervalBetweenTaps: TimeInterval = 0.2

    private var numTouches: Int = 0
    private var timer: Timer? {
        didSet {
            oldValue?.invalidate()
        }
    }

    private var singleTapHandled: Bool = false
    private var doubleTapHandled: Bool = false

    private weak var tapDelegate: SingleOrDoubleTapGestureDelegate?

    // MARK: - Event Handling

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)

        if touches.count != 1 {
            state = .failed
        }
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)

        guard !touches.isEmpty else {
            return
        }

        if numTouches == 0 {
            numTouches += 1
            self.state = .changed
            self.singleTapHandled = tapDelegate?.handleSingleTap(self) ?? false
            if self.singleTapHandled {
                endGesture()
            } else {
                // If we _can_ double tap, start a timer and wait for the second tap.
                timer = Timer.scheduledTimer(
                    withTimeInterval: Self.maxIntervalBetweenTaps,
                    repeats: false,
                    block: { [weak self] _ in
                        defer { self?.timer = nil }
                        guard let self else { return }
                        guard self.numTouches == 1 else {
                            return
                        }
                        endGesture()
                    }
                )
            }
        } else if numTouches == 1 {
            numTouches += 1
            self.timer = nil
            self.state = .recognized
            self.doubleTapHandled = tapDelegate?.handleDoubleTap(self) ?? false
            endGesture()
        } else {
            self.state = .failed
        }
    }

    private func endGesture() {
        let wasHandled = self.singleTapHandled || self.doubleTapHandled
        self.state = .ended
        tapDelegate?.didEndGesture(self, wasHandled: wasHandled)
    }

    override public func reset() {
        super.reset()
        numTouches = 0
        singleTapHandled = false
        doubleTapHandled = false
        timer = nil
    }
}

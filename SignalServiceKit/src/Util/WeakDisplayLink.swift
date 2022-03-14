//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public final class WeakDisplayLink: NSObject {
    private lazy var displayLink = CADisplayLink(target: self, selector: #selector(tick))
    private var handler: (WeakDisplayLink) -> Void

    @objc
    public init(handler: @escaping (WeakDisplayLink) -> Void) {
        self.handler = handler
    }

    @objc
    func tick() { handler(self) }

    @objc
    public var isPaused: Bool {
        get { displayLink.isPaused }
        set { displayLink.isPaused = newValue }
    }

    @objc
    public var duration: CFTimeInterval { displayLink.duration }

    @objc
    public var timestamp: CFTimeInterval { displayLink.timestamp }

    @objc
    public var targetTimestamp: CFTimeInterval { displayLink.targetTimestamp }

    @objc
    @available(iOS 15, *)
    public var preferredFrameRateRange: CAFrameRateRange {
        get { displayLink.preferredFrameRateRange }
        set { displayLink.preferredFrameRateRange = newValue }
    }

    @objc
    public func add(to runLoop: RunLoop, forMode mode: RunLoop.Mode) {
        displayLink.add(to: runLoop, forMode: mode)
    }

    @objc
    public func remove(from runLoop: RunLoop, forMode mode: RunLoop.Mode) {
        displayLink.remove(from: runLoop, forMode: mode)
    }

    @objc
    public func invalidate() { displayLink.invalidate() }
}

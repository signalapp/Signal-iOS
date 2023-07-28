//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MetalKit
import SignalServiceKit

/// Produces the actual particle effects used to tile spoilered regions.
public class SpoilerRenderer {

    /// Configuration that applies to every particle within a given spoiler frame.
    public struct Config: Hashable, Equatable {
        // The first particle set will have this alpha
        fileprivate let maxAlpha: CGFloat
        // Subsequent particle sets will reduce their alpha by this much.
        fileprivate let alphaDropoffRate: CGFloat
        public let particleSizePixels: UInt8
        fileprivate let color: ThemedColor

        public static func standard(color: ThemedColor) -> Self {
            return .init(
                maxAlpha: 0.9,
                alphaDropoffRate: 0.15,
                particleSizePixels: 2,
                color: color
            )
        }

        public static func highlight(color: ThemedColor) -> Self {
            return .init(
                maxAlpha: 0.9,
                alphaDropoffRate: 0.05,
                particleSizePixels: 3,
                color: color
            )
        }

        // Values from 0 to 255.
        var colorRGB: SIMD3<UInt8> {
            var (r, g, b): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
            color.forCurrentTheme.getRed(&r, green: &g, blue: &b, alpha: nil)
            return .init(
                UInt8(clamping: Int(r * 255)),
                UInt8(clamping: Int(g * 255)),
                UInt8(clamping: Int(b * 255))
            )
        }

        // Value from 0 (transparent) to 255 (opaque).
        var particleBaseAlpha: UInt8 {
            return UInt8(clamping: Int(maxAlpha * 255))
        }

        // Value from 0 (transparent) to 255 (opaque).
        var particleAlphaDropoff: UInt8 {
            return UInt8(clamping: Int(alphaDropoffRate * 255))
        }
    }

    /// A single frame into which to render spoilers.
    public struct SpoilerFrame {
        public var frame: CGRect
        public var surfaceArea: SurfaceArea
        public var config: Config
    }

    /// A set of spoiler frames within a larger boundingRect.
    /// The boundingRect is expressed in the containing view's coordinates,
    /// and is no larger than SpoilerMetalConfiguration.maxTextureDimensionPoints
    /// on either dimension.
    /// If a view is larger than a single spec can fit, multiple specs must
    /// be provided to tile the entire view.
    public struct Spec {
        public var spoilerFrames: [SpoilerFrame]
        public var totalSurfaceArea: SurfaceArea
        public var boundingRect: CGRect
    }

    private let metalConfig: SpoilerMetalConfiguration

    public init(metalConfig: SpoilerMetalConfiguration) {
        self.metalConfig = metalConfig

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterForeground),
            name: .OWSApplicationWillEnterForeground,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector:
                #selector(didEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector:
                #selector(reduceMotionSettingChanged),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Prepares a view for rendering spoilers, before actually having spoilers available
    /// to render. (e.g. adds necessary subviews).
    /// Only prepares a single tile at most.
    public func prepareForRendering(onto view: UIView) {
        if view.subviews.contains(where: { $0 is SpoilerParticleView }) {
            return
        }
        let particleView = SpoilerParticleView(
            metalConfig: metalConfig,
            renderer: self
        )
        particleView.isInUse = false
        view.addSubview(particleView)
    }

    public func render(_ specs: [Spec], onto view: UIView) {
        // We pop from this array as we use the views.
        var particleViews = view.subviews.compactMap { $0 as? SpoilerParticleView }
        for spec in specs {
            let particleView: SpoilerParticleView = {
                if particleViews.isEmpty.negated {
                    let existing = particleViews.remove(at: 0)
                    if !existing.isInUse {
                        existing.isInUse = true
                        self.particleViews.append(Weak(value: existing))
                    }
                    return existing
                } else {
                    let particleView = SpoilerParticleView(
                        metalConfig: metalConfig,
                        renderer: self
                    )
                    particleView.isInUse = true
                    self.particleViews.append(Weak(value: particleView))
                    view.addSubview(particleView)
                    return particleView
                }
            }()
            particleView.isHidden = specs.isEmpty
            particleView.frame = spec.boundingRect
            particleView.setSpec(spec)
            particleView.commitChanges()
            didChangeAnimationState()
        }
        // Remove any extra, unused views.
        removeSpoilerViews(particleViews)
    }

    public func removeSpoilerViews(from view: UIView) {
        removeSpoilerViews(view.subviews.lazy
            .compactMap { $0 as? SpoilerParticleView }
       )
    }

    private func removeSpoilerViews(_ spoilerViews: [SpoilerParticleView]) {
        // We hide, instead of actually removing, so we can
        // efficiently reuse them later (as often happens
        // with table view cell reuse).
        var removedViews = Set<SpoilerParticleView>()
        spoilerViews
            .forEach {
                $0.isHidden = true
                removedViews.insert($0)
            }
        // Cull from our tracked views.
        if particleViews.isEmpty.negated {
            let particleViewsCount = particleViews.count
            for offsetFromEnd in 1...particleViews.count {
                let index = particleViewsCount - offsetFromEnd
                let weakView = particleViews[index]
                guard let view = weakView.value else {
                    particleViews.remove(at: index).value?.isInUse = false
                    continue
                }
                if removedViews.contains(view) {
                    particleViews.remove(at: index).value?.isInUse = false
                }
            }
        }
        didChangeAnimationState()
    }

    private var particleViews = [Weak<SpoilerParticleView>]()

    // MARK: - Time management

    // We report the "duration" of the animation to our Metal shader on the
    // hot path for rendering, so we need that to be as efficient as conceivably
    // possible, down to using primitive types.
    // The principle here is while we are animating, we keep the start time and
    // subtract it from the current time. When we pause, we put the current duration
    // into `extraAnimationDurationMs`, and remove the start time. When we resume again,
    // we set a new start time and add the extra duration. This means if we animate
    // for 5 seconds, pause for 2, and animate for 2 again, the "duration" will be
    // 7 (2 duration + 5 "extra").

    // If nil, we are not currently animating and therefore not tracking time changes.
    private var animationStartMs: UInt32?
    private var extraAnimationDurationMs: UInt32 = 0

    // Reset duration every hour so numbers don't get too big.
    private static var maxDurationMs: UInt32 = 60 * 60 * 1000

    private func didChangeAnimationState() {
        self.particleViews.removeAll(where: { $0.value == nil })
        let wantsToAnimate =
            isAppInForeground
            && !UIAccessibility.isReduceMotionEnabled
            && !self.particleViews.isEmpty
        let wasAnimating = animationStartMs != nil

        guard wantsToAnimate != wasAnimating else {
            return
        }

        // Ok to drop higher order bits; we only care about duration
        // measured in shorter timescales.
        let currentDateMs = UInt32(truncatingIfNeeded: Date().ows_millisecondsSince1970)
        if wantsToAnimate {
            // resuming, set the current date (and preserve any extra)
            animationStartMs = currentDateMs
        } else {
            // pausing, write the current duration to the extra.
            extraAnimationDurationMs += currentDateMs - (animationStartMs ?? currentDateMs)
            if extraAnimationDurationMs > Self.maxDurationMs {
                extraAnimationDurationMs = 0
            }
            animationStartMs = nil
        }
    }

    /// This method is on the hot path of rendering; should be as efficient as possible.
    public func getAnimationDuration() -> UInt32 {
        guard let animationStartMs else {
            return extraAnimationDurationMs
        }
        // Ok to drop higher order bits; we only care about duration
        // measured in shorter timescales.
        let currentDateMs = UInt32(truncatingIfNeeded: Date().ows_millisecondsSince1970)
        let duration = (currentDateMs - animationStartMs) + extraAnimationDurationMs
        if duration > Self.maxDurationMs {
            self.extraAnimationDurationMs = 0
            self.animationStartMs = currentDateMs
            return 0
        } else {
            return duration
        }
    }

    // MARK: - Events

    private var isAppInForeground = true { didSet { didChangeAnimationState() }}

    @objc
    private func didEnterForeground() {
        isAppInForeground = true
    }

    @objc
    private func didEnterBackground() {
        isAppInForeground = false
    }

    @objc
    private func reduceMotionSettingChanged() {
        didChangeAnimationState()
    }
}

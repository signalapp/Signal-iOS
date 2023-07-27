//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public typealias SurfaceArea = CGFloat

/// A single rectangle in which to render spoilers.
public struct SpoilerFrame {

    public enum Style: Int {
        /// Fade effect, small particles
        case standard
        /// More solid, larger particles.
        case highlight
    }

    public let frame: CGRect
    public let color: ThemedColor
    public let style: Style

    public init(frame: CGRect, color: ThemedColor, style: Style) {
        self.frame = frame
        self.color = color
        self.style = style
    }
}

/// Conform to this to provide spoiler information (the view to apply spoilers to,
/// the frames of the spoilers, etc) to a `SpoilerableViewAnimator`.
///
/// The UIView itself can conform to `SpoilerableViewAnimator`, but this is
/// not necessarily the case. This flexibility allows using any UIView class for
/// spoiler application, and defining a separate animator, without having to subclass
/// the UIView class in question.
public protocol SpoilerableViewAnimator {

    /// Nullable to enable holding a weak reference; it is assumed the view
    /// is deallocated when returning nil, and observation will be stopped.
    var spoilerableView: UIView? { get }

    /// When the value of this key changes, the spoiler frames are recomputed.
    /// If it is unchanged, frames are assumed to also be unchanged and are reused.
    /// It is assumed computing frames is expensive, and computing the cache key is not.
    var spoilerFramesCacheKey: Int { get }

    func spoilerFrames() -> [SpoilerFrame]

    func equals(_ other: SpoilerableViewAnimator) -> Bool
}

extension SpoilerableViewAnimator {

    public func equals(_ other: SpoilerableViewAnimator) -> Bool {
        guard let view = self.spoilerableView, let otherView = other.spoilerableView else {
            return false
        }
        return view == otherView
    }
}

/// Manages the animations of spoilers on views provided by `SpoilerableViewAnimator`.
/// As long as there is a spoiler to render, renders spoiler particles produced by `SpoilerRenderer`.
/// Stops consuming resources if there are no spoilers to render.
///
/// Sharing an animation manager as much as possible is recommended. This reduces resources by
/// reusing the same state across all views on the same animation manager.
public class SpoilerAnimationManager {

    /// We want to limit how many ranges we render, to put a bound on computational
    /// complexity. A single spoiler range might render across multiple lines and therefore
    /// be broken up into multiple rectangles, so we give a lot of leeway compared to
    /// how many ranges we allow in a body.
    public static let maxSpoilerFrameCount = MessageBodyRanges.maxRangesPerMessage * 4

    // Lazily loaded, but only set once.
    private static let metalConfig: SpoilerMetalConfiguration? = SpoilerMetalConfiguration()

    public static var canRenderAnimatedSpoilers: Bool {
        return FeatureFlags.spoilerAnimations && metalConfig != nil
    }

    private lazy var renderer: SpoilerRenderer? = {
        guard let metalConfig = Self.metalConfig else {
            return nil
        }
        return SpoilerRenderer(metalConfig: metalConfig)
    }()

    public init() {}

    /// Add a view animator. Handles duplicates, so adding is idempotent.
    public func addViewAnimator(_ animator: SpoilerableViewAnimator) {
        if animators.contains(where: { $0.equals(animator)}) {
            return
        }
        animators.append(animator)
        redraw(animator: animator)
    }

    /// Redraw once, forcing a recomputation of all spoiler frames, typically in response to
    /// a frame change or other configuration change on a source view.
    public func didUpdateAnimationState(for animator: SpoilerableViewAnimator) {
        redraw(animator: animator, forceRecomputeFrames: true)
    }

    public func removeViewAnimator(_ animator: SpoilerableViewAnimator) {
        if let view = animator.spoilerableView {
            renderer?.removeSpoilerViews(from: view)
        }
        animators.removeAll(where: {
            // Clear out nil view ones as well.
            $0.equals(animator) || $0.spoilerableView == nil
        })
    }

    // MARK: - Observers

    private var animators: [SpoilerableViewAnimator] = []

    private func redraw(animator: SpoilerableViewAnimator, forceRecomputeFrames: Bool = false) {
        guard Self.canRenderAnimatedSpoilers, let metalConfig = Self.metalConfig else {
            return
        }

        guard let view = animator.spoilerableView else {
            return
        }

        let result = getOrLoadSpoilerSpecs(
            animator: animator,
            forceRecomputeFrames: forceRecomputeFrames,
            viewBounds: view.bounds.size,
            metalConfig: metalConfig
        )
        renderer?.render(result, onto: view)
    }

    // MARK: - Caches

    typealias Spec = SpoilerRenderer.Spec

    // Computing frames is expensive. Doing it periodically, for
    // every bit of text shown on screen, adds up.
    // To avoid this, we cache the last computed frame, and rely on animators
    // to provide a cache key (which should be cheap to compute) to determine
    // when we should discard the cache and recompute frames.
    private var specCache = [Int: [Spec]]()

    private func getOrLoadSpoilerSpecs(
        animator: SpoilerableViewAnimator,
        forceRecomputeFrames: Bool,
        viewBounds: CGSize,
        metalConfig: SpoilerMetalConfiguration
    ) -> [Spec] {
        let cacheKey = animator.spoilerFramesCacheKey
        if !forceRecomputeFrames, let cachedFrames = specCache[cacheKey] {
            return cachedFrames
        }
        let computedFrames = animator.spoilerFrames()
        let result = specs(
            forComputedFrames: computedFrames,
            viewBounds: viewBounds,
            metalConfig: metalConfig
        )
        specCache[cacheKey] = result
        return result
    }

    // MARK: - View subdivision

    private func specs(
        forComputedFrames computedFrames: [SpoilerFrame],
        viewBounds: CGSize,
        metalConfig: SpoilerMetalConfiguration
    ) -> [Spec] {
        // A Metal texture, and by extension an MTKView, can
        // only be of a fixed maximum size. If the view is bigger,
        // break it up into smaller tiles so we can make a separate
        // view/texture for each.
        // A single tile is a single `Spec` in the resulting array.
        // We need to put each spoiler frame into the appropriate tile.
        let tileSize = metalConfig.maxTextureDimensionPoints

        var specs = [Spec]()
        /// tile column -> tile row -> index in `specs`.
        var specIndexMap = [CGFloat: [CGFloat: Int]]()

        for (frameIndex, frame) in computedFrames.enumerated() {
            // Only allow a certain number of frames, then stop.
            if frameIndex > Self.maxSpoilerFrameCount {
                return specs
            }
            let config: SpoilerRenderer.Config = {
                switch frame.style {
                case .standard: return .standard(color: frame.color)
                case .highlight: return .highlight(color: frame.color)
                }
            }()

            // A spoiler frame can span multiple tiles. We need to
            // divide it up between the tiles it intersects.
            let startColumn = floor(frame.frame.minX / tileSize)
            let startRow = floor(frame.frame.minY / tileSize)
            let endColumn = floor(frame.frame.maxX / tileSize)
            let endRow = floor(frame.frame.maxY / tileSize)

            var column: CGFloat = startColumn
            var row: CGFloat = startRow
            while column <= endColumn {
                let tileMinX = column * tileSize
                let tileMaxX = min(viewBounds.width, (column + 1) * tileSize)
                while row <= endRow {
                    let tileMinY = row * tileSize
                    let tileMaxY = min(viewBounds.height, (row + 1) * tileSize)

                    let xInTile = max(0, frame.frame.x - tileMinX)
                    let yInTile = max(0, frame.frame.y - tileMinY)
                    let widthInTile = min(frame.frame.maxX, tileMaxX) - tileMinX - xInTile
                    let heightInTile = min(frame.frame.maxY, tileMaxY) - tileMinY - yInTile
                    let frameInTile = CGRect(
                        x: xInTile,
                        y: yInTile,
                        width: widthInTile,
                        height: heightInTile
                    )
                    let surfaceAreaInTile = frameInTile.width * frameInTile.height
                    let spoilerFrameInTile = SpoilerRenderer.SpoilerFrame(
                        frame: frameInTile,
                        surfaceArea: surfaceAreaInTile,
                        config: config
                    )
                    if
                        let index = specIndexMap[column]?[row],
                        var spec = specs[safe: index]
                    {
                        spec.totalSurfaceArea += surfaceAreaInTile
                        spec.spoilerFrames.append(spoilerFrameInTile)
                        specs[index] = spec
                    } else {
                        let spec = Spec(
                            spoilerFrames: [spoilerFrameInTile],
                            totalSurfaceArea: surfaceAreaInTile,
                            boundingRect: CGRect(
                                x: tileMinX,
                                y: tileMinY,
                                width: tileMaxX - tileMinX,
                                height: tileMaxY - tileMinY
                            )
                        )
                        specs.append(spec)
                        var subMap = specIndexMap[column] ?? [:]
                        subMap[row] = specs.count - 1
                        specIndexMap[column] = subMap
                    }
                    row += 1
                }
                column += 1
            }
        }
        return specs
    }
}

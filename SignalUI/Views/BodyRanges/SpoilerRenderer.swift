//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Produces the actual particle effects used to tile spoilered regions.
/// Does not on its own animate or apply any spoiler animations; `SpoilerAnimationManager`
/// handles that. Instead this class just produces one tile, one frame at a time, and spits them
/// out as pattern image UIColors.
public class SpoilerRenderer {

    /// Should these vary by device? Or drop when getting a memory warning?
    /// Performance is sensitive to these values. Tweak them if it becomes an issue.
    private static let tileWidth: CGFloat = 100
    private static let xOverlayPercent: CGFloat = 0.10
    private static let tileHeight: CGFloat = 40
    private static let yOverlayPercent: CGFloat = 0.25
    private static let particlesPerUnit: CGFloat = 0.06

    private static let particleCount = Int(tileWidth * tileHeight * particlesPerUnit)

    // Must be three layers in sync with the spec below.
    private lazy var particleLayers: [[Particle]] = [
        .random(count: Self.particleCount),
        .random(count: Self.particleCount),
        .random(count: Self.particleCount)
    ]

    public struct Spec: Equatable, Hashable {
        // Must be three alpha values, for the three particle layers.
        // constructors for this spec are private for this reason.
        fileprivate let particleAlphas: [CGFloat]
        fileprivate let particleRadiusPoints: CGFloat
        fileprivate let color: UIColor

        public static func standard(color: UIColor) -> Self {
            return .init(particleAlphas: [0.9, 0.7, 0.5], particleRadiusPoints: 1, color: color)
        }

        public static func highlight(color: UIColor) -> Self {
            return .init(particleAlphas: [0.95, 0.9, 0.85], particleRadiusPoints: 2, color: color)
        }
    }

    /// Drawing each UIImage is expensive. Cache the values we produce on each tick, by spec used to produce it.
    private var tileColors = [Spec: UIColor]()

    public init() {}

    public func getOrRenderTilingColor(_ spec: Spec) -> UIColor {
        return tileColors[spec] ?? render(spec)
    }

    private func render(_ spec: Spec) -> UIColor {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: Self.tileWidth, height: Self.tileHeight), false, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return UIColor.clear
        }
        Self.render(particleLayers: particleLayers, into: context, spec: spec)
        let image = UIGraphicsGetImageFromCurrentImageContext()?.withRenderingMode(.alwaysTemplate) ?? UIImage()
        UIGraphicsEndImageContext()
        let tileColor = UIColor(patternImage: image)
        self.tileColors[spec] = tileColor
        return tileColor
    }

    private static func render(
        particleLayers: [[Particle]],
        into context: CGContext,
        spec: Spec
    ) {
        let width = CGFloat(context.width) / UIScreen.main.scale
        let height = CGFloat(context.height) / UIScreen.main.scale

        guard context.width > 0, context.height > 0 else {
            return
        }

        for (layerIndex, layer) in particleLayers.enumerated() {
            let alpha = spec.particleAlphas[layerIndex]
            context.setFillColor(spec.color.withAlphaComponent(alpha).cgColor)
            for particle in layer {
                // Draw the particle.
                context.fillEllipse(in: CGRect(
                    x: (particle.x) * width,
                    y: (particle.y) * height,
                    width: spec.particleRadiusPoints,
                    height: spec.particleRadiusPoints
                ))
            }
        }
    }

    private var lastTickDate = Date()

    public func resetLastTickDate() {
        self.lastTickDate = Date()
    }

    public func tick() {
        // Wipe the cache.
        tileColors = [:]

        let now = Date()
        let timeDelta = now.timeIntervalSince(lastTickDate)
        lastTickDate = now

        let timeDeltaF = CGFloat(timeDelta)

        for layerIndex in 0..<particleLayers.count {
            for particleIndex in 0..<particleLayers[layerIndex].count {
                var particle = particleLayers[layerIndex][particleIndex]
                defer {
                    particleLayers[layerIndex][particleIndex] = particle
                }
                let newX = particle.x + (timeDeltaF * particle.xVel)
                let newY = particle.y + (timeDeltaF * particle.yVel)
                let outOfBoundsX = newX < -Self.xOverlayPercent || newX > 1 + Self.xOverlayPercent
                let outOfBoundsY = newY < -Self.yOverlayPercent || newY > 1 + Self.yOverlayPercent
                particle.timeRemaining -= timeDelta
                if particle.timeRemaining < 0 || outOfBoundsX || outOfBoundsY {
                    particle.respawn()
                } else {
                    particle.x = newX
                    particle.y = newY
                }
            }
        }
    }

    fileprivate struct Particle {
        // Values from 0 to 1 representing percentage
        // of position across the tile
        var x: CGFloat
        var y: CGFloat
        // Values representing percent of tile dimension
        // moved per second. e.g. 1 = moves tile width in 1 second.
        var xVel: CGFloat
        var yVel: CGFloat
        // Time until the particle disappears.
        var timeRemaining: TimeInterval

        static func random() -> Particle {
            return .init(
                x: .random(in: -SpoilerRenderer.xOverlayPercent...(1 + SpoilerRenderer.xOverlayPercent)),
                y: .random(in: -SpoilerRenderer.yOverlayPercent...(1 + SpoilerRenderer.yOverlayPercent)),
                xVel: .random(in: -0.1...0.1),
                // Y is faster than X because absolute height is smaller.
                yVel: .random(in: -0.5...0.5),
                timeRemaining: .random(in: 1...2)
            )
        }

        mutating func respawn() {
            x = .random(in: -SpoilerRenderer.xOverlayPercent...(1 + SpoilerRenderer.xOverlayPercent))
            y = .random(in: -SpoilerRenderer.yOverlayPercent...(1 + SpoilerRenderer.yOverlayPercent))
            xVel = .random(in: -0.1...0.1)
            // Y is faster than X because absolute height is smaller.
            yVel = .random(in: -0.5...0.5)
            timeRemaining = .random(in: 1...2)
        }
    }
}

extension Array where Element == SpoilerRenderer.Particle {

    static func random(count: Int) -> Self {
        return (0..<count).map { _ in .random() }
    }
}

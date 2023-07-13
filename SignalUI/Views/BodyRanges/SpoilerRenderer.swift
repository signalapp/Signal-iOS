//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SpoilerRenderer {

    // Should these vary by device? Or drop when getting a memory warning?
    private static let tileWidth: CGFloat = 100
    private static let xOverlayPercent: CGFloat = 0.10
    private static let tileHeight: CGFloat = 40
    private static let yOverlayPercent: CGFloat = 0.25
    private static let particlesPerUnit: CGFloat = 0.06
    private static let particleRadiusPoints: CGFloat = 1

    private static let particleCount = Int(tileWidth * tileHeight * particlesPerUnit)

    private lazy var particles: [Particle] =
        .random(alpha: 0.9, count: Self.particleCount)
        + .random(alpha: 0.7, count: Self.particleCount)
        + .random(alpha: 0.5, count: Self.particleCount)

    private var lastDrawDate = Date()

    // Drawing to a UIImage and tiling is reasonably efficient,
    // but there may be further efficiency gains with some other method.
    public var uiImage: UIImage!

    public init() {
        _ = self.render()
    }

    public func render() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: Self.tileWidth, height: Self.tileHeight), false, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return UIImage()
        }
        let now = Date()
        let timeDelta = now.timeIntervalSince(lastDrawDate)
        lastDrawDate = now
        render(particles: &particles, into: context, timeDelta: timeDelta)
        let image = UIGraphicsGetImageFromCurrentImageContext()?.withRenderingMode(.alwaysTemplate) ?? UIImage()
        UIGraphicsEndImageContext()
        self.uiImage = image
        return image
    }

    public func resetLastDrawDate() {
        self.lastDrawDate = Date()
    }

    private func render(
        particles: inout [Particle],
        into context: CGContext,
        timeDelta: TimeInterval
    ) {
        let timeDeltaF = CGFloat(timeDelta)

        let width = CGFloat(context.width) / UIScreen.main.scale
        let height = CGFloat(context.height) / UIScreen.main.scale

        guard context.width > 0, context.height > 0 else {
            return
        }

        var lastAlpha: CGFloat = -1
        for i in 0..<particles.count {
            var particle = particles[i]
            defer {
                particles[i] = particle
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
            if particle.alpha != lastAlpha {
                // Tinting happens separately, only alpha matters.
                context.setFillColor(gray: 1, alpha: particle.alpha)
                lastAlpha = particle.alpha
            }
            // Draw the particle.
            context.fillEllipse(in: CGRect(
                x: (newX) * width,
                y: (newY) * height,
                width: Self.particleRadiusPoints,
                height: Self.particleRadiusPoints
            ))
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

        let alpha: CGFloat

        static func random(alpha: CGFloat) -> Particle {
            return .init(
                x: .random(in: -SpoilerRenderer.xOverlayPercent...(1 + SpoilerRenderer.xOverlayPercent)),
                y: .random(in: -SpoilerRenderer.yOverlayPercent...(1 + SpoilerRenderer.yOverlayPercent)),
                xVel: .random(in: -0.1...0.1),
                // Y is faster than X because absolute height is smaller.
                yVel: .random(in: -0.5...0.5),
                timeRemaining: .random(in: 1...2),
                alpha: alpha
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

    static func random(alpha: CGFloat, count: Int) -> Self {
        return (0..<count).map { _ in .random(alpha: alpha) }
    }
}

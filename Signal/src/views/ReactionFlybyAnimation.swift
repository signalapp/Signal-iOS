//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public class ReactionFlybyAnimation: UIView {
    private static let maxWidth: CGFloat = 500
    let reaction: String
    init(reaction: String) {
        owsAssertDebug(reaction.isSingleEmoji)
        self.reaction = reaction
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(from vc: UIViewController) {
        guard let window = vc.view.window else {
            return owsFailDebug("Unexpectedly missing window")
        }

        window.addSubview(self)
        frame = window.bounds

        if frame.width > Self.maxWidth {
            frame = frame.insetBy(dx: (frame.width - Self.maxWidth) / 2, dy: 0)
        }

        let emoji1Animation = prepareAnimation(
            relativeXPosition: .center(offset: 0),
            relativeStartTime: 0,
            relativeDuration: 0.4,
            size: 25,
            rotation: -27...27
        )

        let emoji2Animation = prepareAnimation(
            relativeXPosition: .center(offset: -60),
            relativeStartTime: 0,
            relativeDuration: 0.44,
            size: 36,
            rotation: -30...0
        )

        let emoji3Animation = prepareAnimation(
            relativeXPosition: .center(offset: 68),
            relativeStartTime: 0,
            relativeDuration: 0.4,
            size: 25,
            rotation: -8...8
        )

        let emoji4Animation = prepareAnimation(
            relativeXPosition: .left(offset: 9),
            relativeStartTime: 0,
            relativeDuration: 0.52,
            size: 32,
            rotation: -12...12
        )

        let emoji5Animation = prepareAnimation(
            relativeXPosition: .center(offset: 45),
            relativeStartTime: 0,
            relativeDuration: 0.56,
            size: 29,
            rotation: -12...12
        )

        let emoji6Animation = prepareAnimation(
            relativeXPosition: .right(offset: 30),
            relativeStartTime: 0,
            relativeDuration: 0.48,
            size: 32
        )

        let emoji7Animation = prepareAnimation(
            relativeXPosition: .center(offset: -9),
            relativeStartTime: 0,
            relativeDuration: 0.64,
            size: 18
        )

        let emoji8Animation = prepareAnimation(
            relativeXPosition: .left(offset: 15),
            relativeStartTime: 0,
            relativeDuration: 0.68,
            size: 32,
            rotation: -8...12
        )

        let emoji9Animation = prepareAnimation(
            relativeXPosition: .left(offset: 52),
            relativeStartTime: 0,
            relativeDuration: 0.8,
            size: 45
        )

        let emoji10Animation = prepareAnimation(
            relativeXPosition: .left(offset: 12),
            relativeStartTime: 0,
            relativeDuration: 1,
            size: 27
        )

        let emoji11Animation = prepareAnimation(
            relativeXPosition: .right(offset: 24),
            relativeStartTime: 0,
            relativeDuration: 0.88,
            size: 22,
            rotation: -4...8
        )

        UIView.animateKeyframes(withDuration: 2.5, delay: 0) {
            emoji1Animation()
            emoji2Animation()
            emoji3Animation()
            emoji4Animation()
            emoji5Animation()
            emoji6Animation()
            emoji7Animation()
            emoji8Animation()
            emoji9Animation()
            emoji10Animation()
            emoji11Animation()
        } completion: { _ in
            self.removeFromSuperview()
        }
    }

    private enum RelativePosition {
        case left(offset: CGFloat)
        case right(offset: CGFloat)
        case center(offset: CGFloat)
    }

    private func prepareAnimation(
        relativeXPosition: RelativePosition,
        relativeStartTime: Double,
        relativeDuration: Double,
        size: CGFloat,
        rotation: ClosedRange<CGFloat>? = nil
    ) -> () -> Void {
        let font = UIFont.systemFont(ofSize: size)

        let label = UILabel()
        label.text = reaction
        label.textAlignment = .center
        label.font = font

        let reactionSize = reaction.boundingRect(
            with: CGSize(square: .greatestFiniteMagnitude),
            options: .init(rawValue: 0),
            attributes: [.font: font],
            context: nil
        ).size

        let container = OWSLayerView(frame: CGRect(origin: .zero, size: reactionSize * 4)) { view in
            label.frame = view.bounds
        }
        container.addSubview(label)
        if let rotation = rotation {
            container.transform = .init(rotationAngle: rotation.lowerBound.toRadians)
        }

        let xPosition: CGFloat
        switch relativeXPosition {
        case .left(let offset):
            xPosition = offset - (container.width / 2) + (reactionSize.width / 2)
        case .right(let offset):
            xPosition = bounds.maxX - container.width - offset + ((container.width - reactionSize.width) / 2)
        case .center(let offset):
            xPosition = bounds.midX - (container.width / 2) + offset
        }
        container.frame.origin = CGPoint(x: xPosition, y: height + container.height)
        addSubview(container)

        return {
            UIView.addKeyframe(withRelativeStartTime: relativeStartTime, relativeDuration: relativeDuration) {
                container.frame.origin.y = -container.height
                if let rotation = rotation {
                    container.transform = .init(rotationAngle: rotation.upperBound.toRadians)
                }
                container.transform = container.transform.scaledBy(x: 2, y: 2)
            }
        }
    }
}

private extension CGFloat {
    var toRadians: CGFloat {
        self * (.pi / 180)
    }
}

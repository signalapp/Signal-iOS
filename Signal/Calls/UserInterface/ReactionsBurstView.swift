//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - UI

class ReactionsBurstView: UIView, ReactionBurstDelegate {
    private let burstAligner: ReactionBurstAligner
    private var burstManager: ReactionBurstManager?

    init(burstAligner: ReactionBurstAligner) {
        self.burstAligner = burstAligner
        super.init(frame: .zero)
        self.burstManager = ReactionBurstManager(burstDelegate: self)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: ReactionBurstDelegate

    func burst(reactions: [Reaction]) {
        guard
            reactions.count == ReactionBurstManager.Constants.reactionCountNeededForBurst,
            let reaction0 = reactions[safe: 0]?.emoji,
            let reaction1 = reactions[safe: 1]?.emoji,
            let reaction2 = reactions[safe: 2]?.emoji
        else {
            owsAssertBeta(false, "Call reaction burst requires \(ReactionBurstManager.Constants.reactionCountNeededForBurst) reactions as input!")
            return
        }

        guard !AppEnvironment.shared.windowManagerRef.isCallInPip else {
            // Don't burst when call is minimized.
            return
        }

        owsAssertDebug(reaction0.isSingleEmoji)
        owsAssertDebug(reaction1.isSingleEmoji)
        owsAssertDebug(reaction2.isSingleEmoji)
        let labels = [
            self.emojiLabel(reaction: reaction0),
            self.emojiLabel(reaction: reaction0),
            self.emojiLabel(reaction: reaction1),
            self.emojiLabel(reaction: reaction1),
            self.emojiLabel(reaction: reaction2),
            self.emojiLabel(reaction: reaction2),
        ]

        let emoji0Animation = prepareAnimation(
            label: labels[0],
            relativeDuration: 0.4,
            scaleFactor: 2,
            rotation: -27...27
        )

        let emoji1Animation = prepareAnimation(
            label: labels[1],
            relativeDuration: 0.54,
            scaleFactor: 2.5,
            rotation: -30...0
        )

        let emoji2Animation = prepareAnimation(
            label: labels[2],
            relativeDuration: 0.6,
            scaleFactor: 3,
            rotation: -8...8
        )

        let emoji3Animation = prepareAnimation(
            label: labels[3],
            relativeDuration: 0.85,
            scaleFactor: 3,
            rotation: -12...12
        )

        let emoji4Animation = prepareAnimation(
            label: labels[4],
            relativeDuration: 0.65,
            scaleFactor: 2.5,
            rotation: -12...12
        )

        let emoji5Animation = prepareAnimation(
            label: labels[5],
            relativeDuration: 0.7,
            scaleFactor: 2
        )

        UIView.animateKeyframes(withDuration: 2.5, delay: 0) {
            emoji0Animation()
            emoji1Animation()
            emoji2Animation()
            emoji3Animation()
            emoji4Animation()
            emoji5Animation()
        } completion: { _ in
            labels.forEach {
                $0.removeFromSuperview()
            }
        }
    }

    private func emojiLabel(reaction: String) -> UILabel {
        let font = UIFont.systemFont(ofSize: burstAligner.emojiStartingSize())
        let label = UILabel()
        label.text = reaction
        label.textAlignment = .center
        label.font = font
        return label
    }

    private func prepareAnimation(
        label: UILabel,
        relativeDuration: Double,
        scaleFactor: CGFloat,
        rotation: ClosedRange<CGFloat>? = nil
    ) -> () -> Void {
        let reactionSize = label.intrinsicContentSize
        let container = OWSLayerView(frame: CGRect(origin: .zero, size: reactionSize * 4)) { view in
            label.frame = view.bounds
        }
        container.addSubview(label)
        if let rotation = rotation {
            container.transform = .init(rotationAngle: rotation.lowerBound.toRadians)
        }

        let position = burstAligner.burstStartingPoint(in: self)

        container.frame.origin = CGPoint(
            x: position.x - container.width/4 - reactionSize.width/2,
            y: position.y - container.height/4-reactionSize.height/2
        )
        addSubview(container)

        return {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: relativeDuration) {
                container.frame.origin.y = -container.height
                if let rotation = rotation {
                    container.transform = .init(rotationAngle: rotation.upperBound.toRadians)
                }
                container.transform = container.transform.scaledBy(x: scaleFactor, y: scaleFactor)
            }
        }
    }
}

private extension CGFloat {
    var toRadians: CGFloat {
        self * (.pi / 180)
    }
}

// MARK: - ReactionReceiver

extension ReactionsBurstView: ReactionReceiver {
    func addReactions(reactions: [Reaction]) {
        reactions.forEach {
            burstManager?.add(reaction: $0)
        }
    }
}

// MARK: - ReactionBurstAligner

protocol ReactionBurstAligner {
    func burstStartingPoint(in view: UIView) -> CGPoint
    func emojiStartingSize() -> CGFloat
}

// MARK: - RotatingArray data structure

private class RotatingArray<T: Timestamped> {
    private let capacity: Int
    private let timespan: TimeInterval

    private var array = [T]()

    init(capacity: Int, timespan: TimeInterval) {
        self.capacity = capacity
        self.timespan = timespan
    }

    func toArray() -> [T] {
        return array
    }

    func append(_ item: T) {
        AssertIsOnMainThread()
        if array.count == capacity {
            array.removeFirst()
        }
        array.append(item)
    }

    func removeAll() {
        array.removeAll()
    }

    func removeAll(where shouldFilter: (T) -> Bool) {
        array.removeAll(where: {
            shouldFilter($0)
        })
    }

    func atCapacityAndWithinTimespan(compareToNow: Bool = false) -> Bool {
        guard array.count == capacity, let first = array[safe: 0] else {
            return false
        }
        let timeElapsed: TimeInterval
        if compareToNow {
            timeElapsed = Date.timeIntervalSinceReferenceDate - first.timestamp
        } else {
            if let last = array[safe: array.count - 1] {
                timeElapsed = last.timestamp - first.timestamp
            } else {
                return false
            }
        }
        return timeElapsed <= self.timespan
    }
}

// MARK: Timestamped

private protocol Timestamped {
    var timestamp: TimeInterval { get }
}
extension Reaction: Timestamped {}

// MARK: - ReactionBurstDelegate

protocol ReactionBurstDelegate: AnyObject {
    func burst(reactions: [Reaction])
}

// MARK: - ReactionBurstManager

class ReactionBurstManager {
    private var incomingEmojiDictionary = [String: RotatingArray<Reaction>]()
    private var cooloffDictionary = [String: TimeInterval]()
    private weak var burstDelegate: ReactionBurstDelegate?
    private var recentBursts = RotatingArray<Burst>(
        capacity: Constants.maxBurstsInTimespan,
        timespan: Constants.timespanForMaxBursts
    )

    private struct Burst: Timestamped {
        var timestamp: TimeInterval
    }

    enum Constants {
        // Three different people must react the same emoji in a span of 4 seconds in order
        // for a burst to occur. The same emoji in different skintones counts as the same
        // emoji, though we will burst proportionate to the variations.
        static let reactionCountNeededForBurst = 3
        static let timespanDuringWhichReactionsMustOccur: TimeInterval = 4

        // After a burst, the amount of time the emoji must wait to be burst-eligible again.
        static let perEmojiCooloffTime: TimeInterval = 2

        // We only want to burst overall 3 times within 4 seconds. This rule is NOT on a
        // per emoji basis. It applies across all bursts for all emojis.
        static let maxBurstsInTimespan = 3
        static let timespanForMaxBursts: TimeInterval = 4
    }

    init(burstDelegate: ReactionBurstDelegate) {
        self.burstDelegate = burstDelegate
    }

    func add(reaction: Reaction) {
        AssertIsOnMainThread()

        let skintonedEmoji = reaction.emoji
        // Different skintones of the same emoji should all go in the array of the base emoji, as
        // they all contribute to the same burst. But if we can't get a base emoji, fallback to
        // the emoji itself.
        let key = EmojiWithSkinTones(rawValue: skintonedEmoji)?.baseEmoji.rawValue ?? skintonedEmoji

        let array: RotatingArray<Reaction>
        if let rxnArray = incomingEmojiDictionary[key] {
            array = rxnArray
        } else {
            let rxnArray = RotatingArray<Reaction>(
                capacity: Constants.reactionCountNeededForBurst,
                timespan: Constants.timespanDuringWhichReactionsMustOccur
            )
            incomingEmojiDictionary[key] = rxnArray
            array = rxnArray
        }

        // Maintain invariant: the per-emoji rotating array only ever has up to one
        // reaction from a given ACI - the latest one. This helps us to ensure that
        // reactions are only triggered when the reaction threshold is fulfilled by
        // `Constants.reactionCountNeededForBurst` _distinct_ ACIs.
        array.removeAll(where: { rxn in
            return rxn.aci == reaction.aci
        })

        array.append(reaction)

        let thresholdMet = array.atCapacityAndWithinTimespan()
        var isEmojiCoolingOff = false
        if
            let lastOccurrenceTime = self.cooloffDictionary[key],
            Date.timeIntervalSinceReferenceDate - lastOccurrenceTime < Constants.perEmojiCooloffTime
        {
            isEmojiCoolingOff = true
        }
        let areBurstsShutOff = self.recentBursts.atCapacityAndWithinTimespan(compareToNow: true)

        if thresholdMet && !isEmojiCoolingOff && !areBurstsShutOff {
            self.burstDelegate?.burst(reactions: array.toArray())
            array.removeAll()
            cooloffDictionary[key] = Date.timeIntervalSinceReferenceDate
            self.recentBursts.append(Burst(timestamp: Date.timeIntervalSinceReferenceDate))
        }
    }
}

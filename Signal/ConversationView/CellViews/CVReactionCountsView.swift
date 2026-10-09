//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class CVReactionCountsView: ManualStackView {

    enum PillState: Equatable {
        case emoji(emoji: String, count: Int, fromLocalUser: Bool)
        case moreCount(count: Int, fromLocalUser: Bool)

        var fromLocalUser: Bool {
            switch self {
            case .emoji(_, _, let fromLocalUser):
                return fromLocalUser
            case .moreCount(_, let fromLocalUser):
                return fromLocalUser
            }
        }
    }

    struct State: Equatable {
        var pill1: PillState
        var pill2: PillState?
        var pill3: PillState?
    }

    static let height: CGFloat = 24
    static let inset: CGFloat = 7

    private static let pillKey1 = "pill1"
    private static let pillKey2 = "pill2"
    private static let pillKey3 = "pill3"

    private let pill1 = PillView(pillKey: CVReactionCountsView.pillKey1)
    private let pill2 = PillView(pillKey: CVReactionCountsView.pillKey2)
    private let pill3 = PillView(pillKey: CVReactionCountsView.pillKey3)

    init() {
        super.init(name: "reaction counts")
    }

    static var stackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal, alignment: .fill, spacing: 0, layoutMargins: .zero)
    }

    static func buildState(with reactionState: InteractionReactionState) -> State {
        func buildPillState(emojiCount: InteractionReactionState.EmojiCount) -> PillState {
            .emoji(
                emoji: emojiCount.emojiVariant,
                count: emojiCount.count,
                fromLocalUser: emojiCount.emojiVariant == reactionState.localUserEmojiVariant,
            )
        }

        // We display up to 3 reaction bubbles per message in order of popularity
        // (`emojiCounts` comes pre-sorted to reflect this ordering).

        var emojiCounts = reactionState.emojiCounts[...]

        // We always have at least one pill.
        let emojiCount1 = emojiCounts.removeFirst()
        let pill1 = buildPillState(emojiCount: emojiCount1)

        guard !emojiCounts.isEmpty else {
            return State(pill1: pill1)
        }

        let emojiCount2 = emojiCounts.removeFirst()
        let pill2 = buildPillState(emojiCount: emojiCount2)

        guard !emojiCounts.isEmpty else {
            return State(pill1: pill1, pill2: pill2)
        }

        let pill3: PillState
        if emojiCounts.count == 1 {
            let emojiCount3 = emojiCounts.removeFirst()
            pill3 = buildPillState(emojiCount: emojiCount3)
        } else {
            // If there are more than 3 unique reactions, the third bubble will
            // represent the count of remaining unique reactors *not* the count of
            // remaining unique emoji.
            let remainingReactionsCount = emojiCounts.lazy.map(\.count).reduce(0, +)
            let remainingReactionsIncludeLocalUser = emojiCounts.contains(where: { $0.emojiVariant == reactionState.localUserEmojiVariant })
            pill3 = .moreCount(count: remainingReactionsCount, fromLocalUser: remainingReactionsIncludeLocalUser)
        }
        return State(pill1: pill1, pill2: pill2, pill3: pill3)
    }

    private static let measurementKey = "CVReactionCountsView"

    /// Bound message for reuse-safe entrance playback.
    private var messageId: String?

    func configure(state: State, cellMeasurement: CVCellMeasurement, messageId: String) {
        self.messageId = messageId

        layer.borderColor = Theme.backgroundColor.cgColor

        var subviews = [UIView]()
        func configure(pillView: PillView, pillState: PillState?) {
            guard let pillState else {
                return
            }
            pillView.configure(pillState: pillState, cellMeasurement: cellMeasurement)
            subviews.append(pillView)
        }
        configure(pillView: pill1, pillState: state.pill1)
        configure(pillView: pill2, pillState: state.pill2)
        configure(pillView: pill3, pillState: state.pill3)

        self.configure(
            config: Self.stackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey,
            subviews: subviews,
        )

        // One flow: local add marks pending in ReactionManager; pill plays when rendered.
        if ReactionManager.pendingReactionEntrances.remove(messageId) {
            playEntranceWhenReady(messageId: messageId, triesLeft: 60)
        }
    }

    static func measure(
        state: State,
        measurementBuilder: CVCellMeasurement.Builder,
    ) -> CGSize {
        var subviewInfos = [ManualStackSubviewInfo]()
        func measurePill(pillState: PillState?, pillKey: String) {
            guard let pillState else {
                return
            }
            let pillSize = PillView.measure(
                pillState: pillState,
                pillKey: pillKey,
                measurementBuilder: measurementBuilder,
            )
            subviewInfos.append(pillSize.asManualSubviewInfo)
        }
        measurePill(pillState: state.pill1, pillKey: Self.pillKey1)
        measurePill(pillState: state.pill2, pillKey: Self.pillKey2)
        measurePill(pillState: state.pill3, pillKey: Self.pillKey3)

        let stackMeasurement = ManualStackView.measure(
            config: Self.stackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey,
            subviewInfos: subviewInfos,
        )
        return stackMeasurement.measuredSize
    }

    override func reset() {
        messageId = nil
        super.reset()

        pill1.reset()
        pill2.reset()
        pill3.reset()
    }

    private func playEntranceWhenReady(messageId: String, triesLeft: Int) {
        guard self.messageId == messageId else { return }
        if bounds.width > 0 {
            pill1.playEntrancePop()
            return
        }
        guard triesLeft > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.playEntranceWhenReady(messageId: messageId, triesLeft: triesLeft - 1)
        }
    }

    // MARK: -

    private class PillView: ManualStackViewWithLayer {

        private let pillKey: String

        /// Stack lays out the wrap (sets frame). Transform animates on the label inside.
        private let emojiWrap = ManualLayoutView(name: "reaction emoji wrap")
        private let emojiLabel = CVLabel()
        private let countLabel = CVLabel()
        /// Blocks configure/reset from killing in-flight pop (was the subtle snap).
        private var isPlayingEntrance = false

        private static let pillBorderWidth: CGFloat = 1

        init(pillKey: String) {
            self.pillKey = pillKey

            super.init(name: pillKey)

            emojiLabel.clipsToBounds = true
            emojiWrap.addSubview(emojiLabel)
            emojiWrap.addLayoutBlock { [weak emojiLabel] view in
                emojiLabel?.frame = view.bounds
            }
            clipsToBounds = true
        }

        static var stackConfig: CVStackViewConfig {
            let layoutMargins = UIEdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)
            return CVStackViewConfig(axis: .horizontal, alignment: .fill, spacing: 2, layoutMargins: layoutMargins)
        }

        static func emojiLabelConfig(pillState: PillState) -> CVLabelConfig? {
            switch pillState {
            case .emoji(let emoji, _, _):
                assert(emoji.isSingleEmoji)

                // textColor doesn't matter for emoji.
                return CVLabelConfig.unstyledText(
                    emoji,
                    font: .boldSystemFont(ofSize: 14),
                    textColor: .black,
                    textAlignment: .center,
                )
            case .moreCount:
                return nil
            }
        }

        static func countLabelConfig(pillState: PillState) -> CVLabelConfig? {
            let textColor: UIColor = {
                if pillState.fromLocalUser {
                    return Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_gray90
                } else {
                    return Theme.secondaryTextAndIconColor
                }
            }()

            let text: String
            switch pillState {
            case .emoji(_, let count, _):
                guard count > 1 else {
                    return nil
                }
                text = count.abbreviatedString
            case .moreCount(let count, _):
                text = "+" + count.abbreviatedString
            }

            return CVLabelConfig.unstyledText(
                text,
                font: .monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                textColor: textColor,
                textAlignment: .center,
            )
        }

        func configure(
            pillState: PillState,
            cellMeasurement: CVCellMeasurement,
        ) {
            if !isPlayingEntrance {
                layer.removeAllAnimations()
                transform = .identity
                alpha = 1
                emojiLabel.transform = .identity
                emojiLabel.alpha = 1
                clipsToBounds = true
            }

            addLayoutBlock { view in
                view.layer.borderWidth = Self.pillBorderWidth
                view.layer.cornerRadius = CVReactionCountsView.height / 2
            }

            layer.borderColor = Theme.backgroundColor.cgColor

            if pillState.fromLocalUser {
                backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray60 : .ows_gray25
            } else {
                backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray05
            }

            var subviews = [UIView]()

            if let emojiLabelConfig = Self.emojiLabelConfig(pillState: pillState) {
                emojiLabelConfig.applyForRendering(label: emojiLabel)
                subviews.append(emojiWrap)
            }

            if let countLabelConfig = Self.countLabelConfig(pillState: pillState) {
                countLabelConfig.applyForRendering(label: countLabel)
                subviews.append(countLabel)
            }

            configure(
                config: Self.stackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: pillKey,
                subviews: subviews,
            )
        }

        override func reset() {
            stopEntrancePop()
            super.reset()
        }

        func playEntrancePop() {
            guard !isPlayingEntrance else { return }
            isPlayingEntrance = true

            // Subtle fast chip appear (scale/alpha only — layout frame stays put).
            alpha = 0
            transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            UIView.animate(
                withDuration: 0.14,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
            ) {
                self.alpha = 1
                self.transform = .identity
            }

            // Emoji pop into the chip.
            clipsToBounds = false
            emojiLabel.alpha = 0
            emojiLabel.transform = CGAffineTransform(translationX: 0, y: -40).scaledBy(x: 0.4, y: 0.4)

            // Peak ~14pt emoji +5px ≈ 1.36 scale; land back to identity in the pill.
            UIView.animateKeyframes(withDuration: 0.42, delay: 0, options: []) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.38) {
                    self.emojiLabel.alpha = 1
                    self.emojiLabel.transform = CGAffineTransform(translationX: 0, y: -40).scaledBy(x: 1.36, y: 1.36)
                }
                UIView.addKeyframe(withRelativeStartTime: 0.38, relativeDuration: 0.62) {
                    self.emojiLabel.transform = .identity
                }
            } completion: { [weak self] _ in
                self?.finishEntrancePop()
            }
        }

        private func stopEntrancePop() {
            layer.removeAllAnimations()
            emojiLabel.layer.removeAllAnimations()
            finishEntrancePop()
        }

        private func finishEntrancePop() {
            isPlayingEntrance = false
            transform = .identity
            alpha = 1
            emojiLabel.transform = .identity
            emojiLabel.alpha = 1
            clipsToBounds = true
        }

        static func measure(
            pillState: PillState,
            pillKey: String,
            measurementBuilder: CVCellMeasurement.Builder,
        ) -> CGSize {

            var subviewInfos = [ManualStackSubviewInfo]()
            if let emojiLabelConfig = Self.emojiLabelConfig(pillState: pillState) {
                let labelSize = CVText.measureLabel(
                    config: emojiLabelConfig,
                    maxWidth: .greatestFiniteMagnitude,
                )
                subviewInfos.append(labelSize.asManualSubviewInfo)
            }

            if let countLabelConfig = Self.countLabelConfig(pillState: pillState) {
                let labelSize = CVText.measureLabel(
                    config: countLabelConfig,
                    maxWidth: .greatestFiniteMagnitude,
                )
                subviewInfos.append(labelSize.asManualSubviewInfo)
            }

            let stackMeasurement = ManualStackView.measure(
                config: Self.stackConfig,
                measurementBuilder: measurementBuilder,
                measurementKey: pillKey,
                subviewInfos: subviewInfos,
            )
            var result = stackMeasurement.measuredSize
            // Pin height.
            result.height = CVReactionCountsView.height
            return result
        }
    }
}

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

    private static let visibleByMessageId = NSMapTable<NSString, CVReactionCountsView>.strongToWeakObjects()

    private enum EntranceKind {
        case local
        case remote
    }

    private var messageId: String?
    private var pendingEntrance: EntranceKind?
    private var entranceScheduled = false
    private var lastSaneSize: CGSize?

    private var localPill: PillView {
        [pill1, pill2, pill3].first(where: \.fromLocalUser) ?? pill1
    }

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

    func configure(state: State, cellMeasurement: CVCellMeasurement, messageId: String) {
        if let previous = self.messageId, previous != messageId {
            Self.visibleByMessageId.removeObject(forKey: previous as NSString)
        }
        self.messageId = messageId
        Self.visibleByMessageId.setObject(self, forKey: messageId as NSString)

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

        if ReactionLayoutPending.localEntrances.remove(messageId) {
            pendingEntrance = .local
            entranceScheduled = false
            lastSaneSize = nil
        } else if ReactionLayoutPending.remoteEntrances.remove(messageId) {
            pendingEntrance = .remote
            entranceScheduled = false
            lastSaneSize = nil
        }
        layer.removeAllAnimations()
        transform = .identity
        switch pendingEntrance {
        case .local:
            // Hidden until stable pill size; then dymek+heart overlap the expand.
            alpha = 0
            localPill.prepareForLocalEntranceFlight()
            // Wait for flush after expand starts — avoids first-frame stretch glitch.
        case .remote:
            alpha = 0
        case .none:
            alpha = 1
        }
    }

    static func flushPendingPops() {
        AssertIsOnMainThread()
        guard let views = visibleByMessageId.objectEnumerator()?.allObjects as? [CVReactionCountsView] else {
            return
        }
        for view in views {
            view.scheduleEntranceIfNeeded()
        }
    }

    private func scheduleEntranceIfNeeded() {
        guard pendingEntrance != nil, !entranceScheduled else { return }
        entranceScheduled = true
        lastSaneSize = nil
        whenPillSized(triesLeft: 12) { [weak self] in
            guard let self, let kind = self.pendingEntrance else { return }
            guard self.hasSanePillBounds else {
                self.entranceScheduled = false
                return
            }
            self.pendingEntrance = nil
            self.entranceScheduled = false
            self.lastSaneSize = nil
            switch kind {
            case .local:
                self.playLocalEntrance()
            case .remote:
                self.playRemoteEntrance()
            }
        }
    }

    private var hasSanePillBounds: Bool {
        // Tight gate — stretched mid-layout frames must not pass (giant box).
        abs(bounds.height - Self.height) < 1.5
            && bounds.width > 18
            && bounds.width < 72
    }

    private func whenPillSized(triesLeft: Int, play: @escaping () -> Void) {
        layoutIfNeeded()
        if hasSanePillBounds {
            let size = bounds.size
            // Two stable frames — kills one-frame teleport / giant flash on ProMotion.
            if let last = lastSaneSize,
               abs(last.width - size.width) < 0.5,
               abs(last.height - size.height) < 0.5 {
                play()
                return
            }
            lastSaneSize = size
        } else {
            lastSaneSize = nil
        }
        guard triesLeft > 0 else {
            entranceScheduled = false
            lastSaneSize = nil
            // Never show a stretched pill.
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.whenPillSized(triesLeft: triesLeft - 1, play: play)
        }
    }

    private func playLocalEntrance() {
        guard hasSanePillBounds else { return }
        layer.removeAllAnimations()
        // Dymek + heart together with expand (not after it).
        alpha = 1
        transform = .identity
        localPill.playLocalEntrancePop()
    }

    private func playRemoteEntrance() {
        guard hasSanePillBounds else { return }
        layer.removeAllAnimations()
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
        let animator = UIViewPropertyAnimator(duration: 0.15, springDamping: 0.78, springResponse: 0.15)
        animator.addAnimations {
            self.alpha = 1
            self.transform = .identity
        }
        animator.startAnimation()
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
        if let messageId, Self.visibleByMessageId.object(forKey: messageId as NSString) === self {
            Self.visibleByMessageId.removeObject(forKey: messageId as NSString)
        }
        messageId = nil
        pendingEntrance = nil
        entranceScheduled = false
        lastSaneSize = nil
        layer.removeAllAnimations()
        alpha = 1
        transform = .identity
        super.reset()

        pill1.reset()
        pill2.reset()
        pill3.reset()
    }

    // MARK: -

    private class PillView: ManualStackViewWithLayer {

        private let pillKey: String

        // WithLayer wrap so flying emoji isn't sliced by pill border.
        private let emojiWrap = ManualLayoutViewWithLayer(name: "reaction emoji wrap")
        private let emojiLabel = CVLabel()
        private let countLabel = CVLabel()
        private(set) var fromLocalUser = false
        private var isPlayingPop = false

        private static let pillBorderWidth: CGFloat = 1

        init(pillKey: String) {
            self.pillKey = pillKey

            super.init(name: pillKey)

            emojiWrap.clipsToBounds = false
            emojiWrap.backgroundColor = .clear
            emojiWrap.isOpaque = false
            emojiLabel.clipsToBounds = false
            emojiLabel.backgroundColor = .clear
            emojiWrap.addSubview(emojiLabel)
            emojiWrap.addLayoutBlock { [weak self, weak emojiLabel] view in
                guard let self, let emojiLabel, emojiLabel.superview === self.emojiWrap else { return }
                emojiLabel.frame = view.bounds
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
            fromLocalUser = pillState.fromLocalUser

            if !isPlayingPop {
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

        func prepareForLocalEntranceFlight() {
            alpha = 1
            transform = .identity
            emojiLabel.alpha = 0
            emojiLabel.transform = CGAffineTransform(translationX: 0, y: -36).scaledBy(x: 0.45, y: 0.45)
        }

        func playLocalEntrancePop() {
            guard beginPop() else {
                alpha = 1
                emojiLabel.alpha = 1
                emojiLabel.transform = .identity
                return
            }

            // Pill already on-screen; only emoji flies in.
            alpha = 1
            transform = .identity
            emojiLabel.alpha = 0
            emojiLabel.transform = CGAffineTransform(translationX: 0, y: -36).scaledBy(x: 0.45, y: 0.45)

            UIView.animateKeyframes(withDuration: 0.28, delay: 0, options: [.allowUserInteraction]) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.35) {
                    self.emojiLabel.alpha = 1
                    self.emojiLabel.transform = CGAffineTransform(translationX: 0, y: -36).scaledBy(x: 1.32, y: 1.32)
                }
                UIView.addKeyframe(withRelativeStartTime: 0.35, relativeDuration: 0.65) {
                    self.emojiLabel.transform = .identity
                }
            } completion: { [weak self] _ in
                self?.finishPop()
            }
        }

        private func beginPop() -> Bool {
            guard !isPlayingPop, let counts = superview else { return false }
            // Only unclip the pill — never the message wrapper (giant layer flash).
            isPlayingPop = true
            clipsToBounds = false
            counts.clipsToBounds = false
            return true
        }

        func finishPop() {
            isPlayingPop = false
            emojiLabel.transform = .identity
            emojiLabel.alpha = 1
            transform = .identity
            alpha = 1
            clipsToBounds = true
            superview?.clipsToBounds = false
        }

        override func reset() {
            isPlayingPop = false
            fromLocalUser = false
            emojiLabel.transform = .identity
            emojiLabel.alpha = 1
            super.reset()
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

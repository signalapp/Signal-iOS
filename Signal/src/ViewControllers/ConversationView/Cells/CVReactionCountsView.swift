//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

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
        let pill1: PillState?
        let pill2: PillState?
        let pill3: PillState?
    }

    public static let height: CGFloat = 24
    public static let inset: CGFloat = 7

    private static let pillKey1 = "pill1"
    private static let pillKey2 = "pill2"
    private static let pillKey3 = "pill3"

    private let pill1 = PillView(pillKey: CVReactionCountsView.pillKey1)
    private let pill2 = PillView(pillKey: CVReactionCountsView.pillKey2)
    private let pill3 = PillView(pillKey: CVReactionCountsView.pillKey3)

    required init() {
        super.init(name: "reaction counts")
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String, arrangedSubviews: [UIView] = []) {
        super.init(name: name, arrangedSubviews: arrangedSubviews)
    }

    static var stackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal, alignment: .fill, spacing: 0, layoutMargins: .zero)
    }

    public static func buildState(with reactionState: InteractionReactionState) -> State {
        func buildPillState(emojiCount: InteractionReactionState.EmojiCount) -> PillState {
            .emoji(emoji: emojiCount.emoji,
                   count: emojiCount.count,
                   fromLocalUser: emojiCount.emoji == reactionState.localUserEmoji)
        }

        // We display up to 3 reaction bubbles per message in order
        // of popularity (`emojiCounts` comes pre-sorted to reflect
        // this ordering).

        var pill1: PillState?
        var pill2: PillState?
        var pill3: PillState?
        let build = {
            State(pill1: pill1, pill2: pill2, pill3: pill3)
        }

        guard !reactionState.emojiCounts.isEmpty else {
            return build()
        }

        pill1 = buildPillState(emojiCount: reactionState.emojiCounts[0])

        guard reactionState.emojiCounts.count >= 2 else {
            return build()
        }

        pill2 = buildPillState(emojiCount: reactionState.emojiCounts[1])

        guard reactionState.emojiCounts.count >= 3 else {
            return build()
        }

        // If there are more than 3 unique reactions, the third bubble
        // will represent the count of remaining unique reactors *not*
        // the count of remaining unique emoji.
        if reactionState.emojiCounts.count > 3 {
            let renderedEmoji = reactionState.emojiCounts[0...1].map { $0.emoji }
            let remainingReactorCount = reactionState.emojiCounts
                .lazy
                .filter { !renderedEmoji.contains($0.emoji) }
                .map { $0.count }
                .reduce(0, +)
            let remainingReactionsIncludesLocalUserReaction: Bool = {
                guard let localEmoji = reactionState.localUserEmoji else { return false }
                return !renderedEmoji.contains(localEmoji)
            }()
            pill3 = .moreCount(count: remainingReactorCount,
                               fromLocalUser: remainingReactionsIncludesLocalUserReaction)
        } else {
            pill3 = buildPillState(emojiCount: reactionState.emojiCounts[2])
        }

        return build()
    }

    private static let measurementKey = "CVReactionCountsView"

    func configure(state: State, cellMeasurement: CVCellMeasurement) {

        layer.borderColor = Theme.backgroundColor.cgColor

        var subviews = [UIView]()
        func configure(pillView: PillView, pillState: PillState?) {
            guard let pillState = pillState else {
                return
            }
            pillView.configure(pillState: pillState, cellMeasurement: cellMeasurement)
            subviews.append(pillView)
        }
        configure(pillView: pill1, pillState: state.pill1)
        configure(pillView: pill2, pillState: state.pill2)
        configure(pillView: pill3, pillState: state.pill3)

        self.configure(config: Self.stackConfig,
                       cellMeasurement: cellMeasurement,
                       measurementKey: Self.measurementKey,
                       subviews: subviews)
    }

    static func measure(state: State,
                        measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        var subviewInfos = [ManualStackSubviewInfo]()
        func measurePill(pillState: PillState?, pillKey: String) {
            guard let pillState = pillState else {
                return
            }
            let pillSize = PillView.measure(pillState: pillState,
                                            pillKey: pillKey,
                                            measurementBuilder: measurementBuilder)
            subviewInfos.append(pillSize.asManualSubviewInfo)
        }
        measurePill(pillState: state.pill1, pillKey: Self.pillKey1)
        measurePill(pillState: state.pill2, pillKey: Self.pillKey2)
        measurePill(pillState: state.pill3, pillKey: Self.pillKey3)

        let stackMeasurement = ManualStackView.measure(config: Self.stackConfig,
                                                       measurementBuilder: measurementBuilder,
                                                       measurementKey: Self.measurementKey,
                                                       subviewInfos: subviewInfos)
        return stackMeasurement.measuredSize
    }

    public override func reset() {
        super.reset()

        pill1.reset()
        pill2.reset()
        pill3.reset()
    }

    // MARK: -

    private class PillView: ManualStackViewWithLayer {

        private let pillKey: String

        private let emojiLabel = CVLabel()
        private let countLabel = CVLabel()

        private static let pillBorderWidth: CGFloat = 1

        required init(pillKey: String) {
            self.pillKey = pillKey

            super.init(name: pillKey)

            emojiLabel.clipsToBounds = true
            clipsToBounds = true
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        required init(name: String, arrangedSubviews: [UIView] = []) {
            fatalError("init(name:arrangedSubviews:) has not been implemented")
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
                return CVLabelConfig(text: emoji,
                                     font: .boldSystemFont(ofSize: 14),
                                     textColor: .black,
                                     textAlignment: .center)
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

            return CVLabelConfig(text: text,
                                 font: .monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                                 textColor: textColor,
                                 textAlignment: .center)
        }

        func configure(pillState: PillState,
                       cellMeasurement: CVCellMeasurement) {

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
                subviews.append(emojiLabel)
            }

            if let countLabelConfig = Self.countLabelConfig(pillState: pillState) {
                countLabelConfig.applyForRendering(label: countLabel)
                subviews.append(countLabel)
            }

            configure(config: Self.stackConfig,
                      cellMeasurement: cellMeasurement,
                      measurementKey: pillKey,
                      subviews: subviews)
        }

        static func measure(pillState: PillState,
                            pillKey: String,
                            measurementBuilder: CVCellMeasurement.Builder) -> CGSize {

            var subviewInfos = [ManualStackSubviewInfo]()
            if let emojiLabelConfig = Self.emojiLabelConfig(pillState: pillState) {
                let labelSize = CVText.measureLabel(config: emojiLabelConfig,
                                                    maxWidth: .greatestFiniteMagnitude)
                subviewInfos.append(labelSize.asManualSubviewInfo)
            }

            if let countLabelConfig = Self.countLabelConfig(pillState: pillState) {
                let labelSize = CVText.measureLabel(config: countLabelConfig,
                                                    maxWidth: .greatestFiniteMagnitude)
                subviewInfos.append(labelSize.asManualSubviewInfo)
            }

            let stackMeasurement = ManualStackView.measure(config: Self.stackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: pillKey,
                                                           subviewInfos: subviewInfos)
            var result = stackMeasurement.measuredSize
            // Pin height.
            result.height = CVReactionCountsView.height
            return result
        }
    }
}

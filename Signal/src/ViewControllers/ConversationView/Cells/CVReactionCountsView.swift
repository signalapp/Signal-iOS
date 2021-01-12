//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

class CVReactionCountsView: OWSStackView {

    struct State: Equatable {
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
        let pill1: PillState?
        let pill2: PillState?
        let pill3: PillState?
    }

    public static let height: CGFloat = 24
    public static let inset: CGFloat = 7

    private let pill1 = PillView()
    private let pill2 = PillView()
    private let pill3 = PillView()

    required init() {
        super.init(name: "reaction counts")

        self.apply(config: Self.stackConfig)

        addArrangedSubview(pill1)
        addArrangedSubview(pill2)
        addArrangedSubview(pill3)

        // low priority contstraint to ensure the view has the smallest width possible.
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            self.autoSetDimension(.width, toSize: 0)
        }
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String, arrangedSubviews: [UIView] = []) {
        super.init(name: name, arrangedSubviews: arrangedSubviews)
    }

    static var stackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal, alignment: .fill, spacing: 0, layoutMargins: .zero)
    }

    public static func buildState(with reactionState: InteractionReactionState) -> State {
        func buildPillState(emojiCount: (emoji: String, count: Int)) -> State.PillState {
            .emoji(emoji: emojiCount.emoji,
                   count: emojiCount.count,
                   fromLocalUser: emojiCount.emoji == reactionState.localUserEmoji)
        }

        // We display up to 3 reaction bubbles per message in order
        // of popularity (`emojiCounts` comes pre-sorted to reflect
        // this ordering).

        var pill1: State.PillState?
        var pill2: State.PillState?
        var pill3: State.PillState?
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

    func configure(withState state: State) {
        configure(pillView: pill1, pillState: state.pill1)
        configure(pillView: pill2, pillState: state.pill2)
        configure(pillView: pill3, pillState: state.pill3)
    }

    private func configure(pillView: PillView, pillState: State.PillState?) {
        guard let pillState = pillState else {
            pillView.isHiddenInStackView = true
            return
        }
        pillView.isHiddenInStackView = false
        pillView.configure(pillState: pillState)
    }

    public static func measure(state: State) -> CGSize {
        var subviewSizes = [CGSize]()
        for pillState in [state.pill1, state.pill2, state.pill3] {
            guard let pillState = pillState else {
                continue
            }
            let pillSize = PillView.measure(pillState: pillState)
            subviewSizes.append(pillSize)
        }
        guard !subviewSizes.isEmpty else {
            owsFailDebug("Missing pills.")
            return .zero
        }
        return CVStackView.measure(config: stackConfig, subviewSizes: subviewSizes)
    }

    private class PillView: OWSLayerView {
        private let emojiLabel = UILabel()
        private let countLabel = UILabel()

        private static let pillBorderWidth: CGFloat = 1

        private let contentsStackView = OWSStackView(name: "pillView")

        required override init() {
            super.init()

            self.layoutCallback = { view in
                view.layer.borderWidth = Self.pillBorderWidth
                view.layer.cornerRadius = CVReactionCountsView.height / 2
            }

            addSubview(contentsStackView)
            contentsStackView.autoSetDimension(.height, toSize: CVReactionCountsView.height)
            contentsStackView.autoPinEdgesToSuperviewEdges()
            contentsStackView.addArrangedSubview(emojiLabel)
            contentsStackView.addArrangedSubview(countLabel)
            contentsStackView.apply(config: Self.stackConfig)

            emojiLabel.clipsToBounds = true
            clipsToBounds = true
        }

        static var stackConfig: CVStackViewConfig {
            let layoutMargins = UIEdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)
            return CVStackViewConfig(axis: .horizontal, alignment: .fill, spacing: 2, layoutMargins: layoutMargins)
        }

        static func emojiLabelConfig(pillState: State.PillState) -> CVLabelConfig? {
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

        static func countLabelConfig(pillState: State.PillState) -> CVLabelConfig? {
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

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configure(pillState: State.PillState) {

            layer.borderColor = Theme.backgroundColor.cgColor

            if pillState.fromLocalUser {
                backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray60 : .ows_gray25
            } else {
                backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray05
            }

            if let emojiLabelConfig = Self.emojiLabelConfig(pillState: pillState) {
                emojiLabel.isHiddenInStackView = false
                emojiLabelConfig.applyForRendering(label: emojiLabel)
            } else {
                emojiLabel.isHiddenInStackView = true
            }

            if let countLabelConfig = Self.countLabelConfig(pillState: pillState) {
                countLabel.isHiddenInStackView = false
                countLabelConfig.applyForRendering(label: countLabel)
            } else {
                countLabel.isHiddenInStackView = true
            }
        }

        static func measure(pillState: State.PillState) -> CGSize {
            var subviewSizes = [CGSize]()

            if let emojiLabelConfig = Self.emojiLabelConfig(pillState: pillState) {
                subviewSizes.append(CVText.measureLabel(config: emojiLabelConfig,
                                                        maxWidth: .greatestFiniteMagnitude))
            }

            if let countLabelConfig = Self.countLabelConfig(pillState: pillState) {
                subviewSizes.append(CVText.measureLabel(config: countLabelConfig,
                                                        maxWidth: .greatestFiniteMagnitude))
            }

            return CVStackView.measure(config: stackConfig, subviewSizes: subviewSizes)
        }
    }
}

//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ReactionCountsView: UIStackView {
    @objc static let height: CGFloat = 22
    @objc static let inset: CGFloat = 6

    private let pill1 = ReactionPillView()
    private let pill2 = ReactionPillView()
    private let pill3 = ReactionPillView()

    init() {
        super.init(frame: .zero)

        addArrangedSubview(pill1)
        addArrangedSubview(pill2)
        addArrangedSubview(pill3)

        // low priority contstraint to ensure the view has the smallest width possible.
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            self.autoSetDimension(.width, toSize: 0)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    func configure(with reactionState: InteractionReactionState) {
        pill1.isHidden = true
        pill2.isHidden = true
        pill3.isHidden = true

        func configure(emojiCount: (emoji: String, count: Int), pillView: ReactionPillView) {
            pillView.configure(
                for: emojiCount.emoji,
                count: emojiCount.count,
                fromLocalUser: emojiCount.emoji == reactionState.localUserEmoji
            )
            pillView.isHidden = false
        }

        // We display up to 3 reaction bubbles per message in order
        // of popularity (`emojiCounts` comes pre-sorted to reflect
        // this ordering).

        guard !reactionState.emojiCounts.isEmpty else { return }

        configure(emojiCount: reactionState.emojiCounts[0], pillView: pill1)

        guard reactionState.emojiCounts.count >= 2 else { return }

        configure(emojiCount: reactionState.emojiCounts[1], pillView: pill2)

        guard reactionState.emojiCounts.count >= 3 else { return }

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
            pill3.configure(
                forMoreCount: remainingReactorCount,
                fromLocalUser: remainingReactionsIncludesLocalUserReaction
            )
        } else {
            configure(emojiCount: reactionState.emojiCounts[2], pillView: pill3)
        }

        pill3.isHidden = false
    }
}

private class ReactionPillView: UIView {
    let emojiLabel = UILabel()
    let countLabel = UILabel()

    let pillBorderWidth: CGFloat = 1

    let contentsStackView = UIStackView()

    init() {
        super.init(frame: .zero)

        addSubview(contentsStackView)
        contentsStackView.autoSetDimension(.height, toSize: ReactionCountsView.height)
        contentsStackView.layoutMargins = UIEdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)
        contentsStackView.isLayoutMarginsRelativeArrangement = true
        contentsStackView.spacing = 2

        contentsStackView.autoPinEdgesToSuperviewEdges()

        contentsStackView.addArrangedSubview(emojiLabel)
        contentsStackView.addArrangedSubview(countLabel)

        emojiLabel.font = .boldSystemFont(ofSize: 12)
        emojiLabel.textAlignment = .center

        countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        countLabel.textAlignment = .center

        layer.borderWidth = pillBorderWidth
        layer.cornerRadius = ReactionCountsView.height / 2

        emojiLabel.clipsToBounds = true
        clipsToBounds = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(for emoji: String, count: Int, fromLocalUser: Bool) {
        assert(emoji.isSingleEmoji)

        configureColors(fromLocalUser: fromLocalUser)

        emojiLabel.text = emoji
        emojiLabel.isHidden = false

        countLabel.text = count.abbreviatedString
        countLabel.isHidden = count <= 1
    }

    func configure(forMoreCount count: Int, fromLocalUser: Bool) {
        configureColors(fromLocalUser: fromLocalUser)

        emojiLabel.isHidden = true

        countLabel.text = "+" + count.abbreviatedString
        countLabel.isHidden = false
    }

    private func configureColors(fromLocalUser: Bool) {
        layer.borderColor = Theme.backgroundColor.cgColor
        backgroundColor = fromLocalUser ? .ows_accentBlue : Theme.isDarkThemeEnabled ? UIColor.ows_gray75 : UIColor.ows_gray05
        countLabel.textColor = fromLocalUser ? .ows_white : Theme.primaryTextColor
    }
}

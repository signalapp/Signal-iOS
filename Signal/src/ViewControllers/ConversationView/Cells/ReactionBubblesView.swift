//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ReactionBubblesView: UIView {
    private let bubble1 = ReactionBubbleView()
    private let bubble2 = ReactionBubbleView()

    init() {
        super.init(frame: .zero)

        autoSetDimension(.height, toSize: 62, relation: .lessThanOrEqual)
        autoSetDimension(.height, toSize: 34, relation: .greaterThanOrEqual)

        addSubview(bubble2)
        addSubview(bubble1)

        bubble1.autoPinEdge(toSuperviewEdge: .top)
        bubble1.autoPinWidthToSuperview()
        bubble2.autoPinWidthToSuperview()
        bubble2.autoPinEdge(toSuperviewEdge: .bottom)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    func configure(with reactionState: InteractionReactionState) {
        bubble1.isHidden = true
        bubble2.isHidden = true

        guard let emojiCounts = reactionState.emojiCounts, !emojiCounts.isEmpty else { return }

        bubble1.configure(for: emojiCounts[0].emoji, fromLocalUser: emojiCounts[0].emoji == reactionState.localUserEmoji)
        bubble1.isHidden = false

        guard emojiCounts.count >= 2 else { return }
        bubble2.configure(for: emojiCounts[1].emoji, fromLocalUser: emojiCounts[1].emoji == reactionState.localUserEmoji)
        bubble2.isHidden = false
    }
}

private class ReactionBubbleView: UIView {
    let label = UILabel()

    let bubbleDiameter: CGFloat = 32
    let bubbleBorderWidth: CGFloat = 1

    init() {
        super.init(frame: .zero)

        label.font = .boldSystemFont(ofSize: 18)
        label.textAlignment = .center
        addSubview(label)
        label.autoSetDimensions(to: CGSize(square: bubbleDiameter))
        label.autoPinEdgesToSuperviewMargins()

        layoutMargins = UIEdgeInsets(top: bubbleBorderWidth, leading: bubbleBorderWidth, bottom: bubbleBorderWidth, trailing: bubbleBorderWidth)

        label.layer.cornerRadius = bubbleDiameter / 2
        layer.cornerRadius = (bubbleDiameter + (bubbleBorderWidth * 2)) / 2

        label.clipsToBounds = true
        clipsToBounds = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(for emoji: String, fromLocalUser: Bool) {
        assert(emoji.isSingleEmoji)

        backgroundColor = Theme.backgroundColor
        label.backgroundColor = fromLocalUser ? .ows_signalBlue : Theme.isDarkThemeEnabled ? UIColor.ows_gray75 : UIColor.ows_gray05
        label.text = emoji
    }
}

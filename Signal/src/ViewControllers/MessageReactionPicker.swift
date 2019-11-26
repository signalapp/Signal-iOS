//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol MessageReactionPickerDelegate: class {
    func didSelectReaction(reaction: String, isRemoving: Bool)
}

class MessageReactionPicker: UIStackView {
    static let emojiSet = ["❤️", "👍", "👎", "😂", "😮", "😢", "😡"]

    let pickerDiameter: CGFloat = 48
    let pickerPadding: CGFloat = 2
    var reactionHeight: CGFloat { return pickerDiameter - (2 * pickerPadding) }

    private var buttonForEmoji = [String: OWSFlatButton]()
    private var selectedEmoji: String?
    private weak var delegate: MessageReactionPickerDelegate?
    private lazy var backgroundView = addBackgroundView(withBackgroundColor: Theme.backgroundColor, cornerRadius: pickerDiameter / 2)
    init(selectedEmoji: String?, delegate: MessageReactionPickerDelegate) {
        self.selectedEmoji = selectedEmoji
        self.delegate = delegate

        super.init(frame: .zero)

        backgroundView.layer.shadowColor = UIColor.black.withAlphaComponent(0.24).cgColor
        backgroundView.layer.shadowOffset = CGSize(width: 0, height: 8)
        backgroundView.layer.shadowOpacity = 1
        backgroundView.layer.shadowRadius = 8

        autoSetDimension(.height, toSize: pickerDiameter)

        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: pickerPadding, leading: pickerPadding, bottom: pickerPadding, trailing: pickerPadding)

        for emoji in MessageReactionPicker.emojiSet {
            let button = OWSFlatButton()
            button.autoSetDimensions(to: CGSize(square: reactionHeight))
            button.setTitle(title: emoji, font: .systemFont(ofSize: 30), titleColor: Theme.primaryTextColor)
            button.setPressedBlock { [weak self] in
                self?.delegate?.didSelectReaction(reaction: emoji, isRemoving: emoji == self?.selectedEmoji)
            }
            buttonForEmoji[emoji] = button
            addArrangedSubview(button)

            // Add a circle behind the currently selected emoji
            if selectedEmoji == emoji {
                let selectedBackgroundView = UIView()
                selectedBackgroundView.backgroundColor = .ows_signalBlue
                selectedBackgroundView.clipsToBounds = true
                selectedBackgroundView.layer.cornerRadius = reactionHeight / 2
                backgroundView.addSubview(selectedBackgroundView)
                selectedBackgroundView.autoPin(toEdgesOf: button)
            }
        }
    }

    func playPresentationAnimation(duration: TimeInterval) {
        backgroundView.alpha = 0
        UIView.animate(withDuration: duration) { self.backgroundView.alpha = 1 }

        let delayStep = duration / Double(arrangedSubviews.count + 1)
        var delay: TimeInterval = 0
        for view in arrangedSubviews {
            view.alpha = 0
            view.transform = CGAffineTransform.scale(1.5).translatedBy(x: 0, y: -15)
            UIView.animate(withDuration: delayStep, delay: delay, options: .curveEaseOut, animations: {
                view.transform = .identity
                view.alpha = 1
            }) { _ in }
            delay += delayStep
        }
    }

    var focusedEmoji: String?
    func updateFocusPosition(_ position: CGPoint, animated: Bool) {
        var previouslyFocusedButton: OWSFlatButton?
        var focusedButton: OWSFlatButton?

        if let focusedEmoji = focusedEmoji, let focusedButton = buttonForEmoji[focusedEmoji] {
            previouslyFocusedButton = focusedButton
        }

        focusedEmoji = nil

        for (emoji, button) in buttonForEmoji {
            guard focusArea(for: button).contains(position) else { continue }
            focusedEmoji = emoji
            focusedButton = buttonForEmoji[emoji]
            break
        }

        // Do nothing if we're already focused
        guard previouslyFocusedButton != focusedButton else { return }

        UIView.animate(withDuration: animated ? 0.15 : 0) {
            previouslyFocusedButton?.transform = .identity
            focusedButton?.transform = CGAffineTransform.scale(1.5).translatedBy(x: 0, y: -15)
        }
    }

    func focusArea(for button: UIView) -> CGRect {
        var focusArea = button.frame

        // This button is currently focused, restore identity while we get the frame
        // as the focus area is always relative to the unfocused state.
        if button.transform != .identity {
            let originalTransform = button.transform
            button.transform = .identity
            focusArea = button.frame
            button.transform = originalTransform
        }

        // Always a fixed height
        focusArea.size.height = 136

        // Allows focus a fixed distance above the reaction bar
        focusArea.origin.y -= 20

        // Encompases the width of the reaction, plus half of the padding on either side
        focusArea.size.width = reactionHeight + pickerPadding
        focusArea.origin.x -= pickerPadding / 2

        return focusArea
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

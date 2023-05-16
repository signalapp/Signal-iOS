//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

class EmojiMoodPickerView: UIView {

    // MARK: - Properties

    var selectedMood: Mood? {
        didSet {
            moodButtons.forEach { (mood, button) in
                button.isSelected = (mood == selectedMood)
            }
        }
    }

    private let moodButtons: [Mood: UIButton] = Mood.allCases.dictionaryMappingToValues { (mood) in
        let button = UIButton(type: .custom)
        let title = NSAttributedString(string: "\(mood.emojiRepresentation)", attributes: [
            .font: UIFont.boldSystemFont(ofSize: 24)
        ])
        button.clipsToBounds = true
        button.setAttributedTitle(title, for: .normal)
        return button
    }

    private let buttonStack: UIStackView = {
        let stackView = UIStackView()
        stackView.spacing = 8
        stackView.distribution = .equalSpacing
        return stackView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(buttonStack)

        let orderedButtons = Mood.allCases.compactMap { moodButtons[$0] }
        for button in orderedButtons {
            button.addTarget(self, action: #selector(buttonWasTapped(_:)), for: .touchUpInside)
            buttonStack.addArrangedSubview(button)
        }

        // Setup layout constraints
        buttonStack.autoPinEdgesToSuperviewEdges()
        for button in moodButtons.values {
            // This should continue to work if we ever want dynamic sizing
            // Though, the padding might need some adjustment
            button.autoPin(toAspectRatio: 1)
            button.autoSetDimension(.height, toSize: 44, relation: .greaterThanOrEqual)
        }

        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        // Ensure button stack is laid out early so we can set the correct corner radius
        buttonStack.layoutIfNeeded()
        for button in moodButtons.values {
            let smallerAxis = button.bounds.size.smallerAxis
            button.layer.cornerRadius = (smallerAxis / 2)
        }
    }

    // MARK: - Button responder

    @objc
    private func buttonWasTapped(_ button: UIButton) {
        // When this action is invoked, our selection state hasn't been updated yet
        // If we were not selected, we're being selected
        // If we were selected, we're being unselected
        let isBeingSelected = !button.isSelected
        selectedMood = isBeingSelected ? mood(for: button) : nil
    }

    private func mood(for button: UIButton) -> Mood? {
        moodButtons.first(where: { $1 == button })?.key
    }

    @objc
    private func applyTheme() {
        let defaultButtonBackground = Theme.isDarkThemeEnabled ? UIColor.ows_gray80 : UIColor.ows_gray05
        let selectedButtonBackground = Theme.accentBlueColor

        moodButtons.values.forEach { (button) in
            button.setBackgroundImage(UIImage(color: defaultButtonBackground), for: .normal)
            button.setBackgroundImage(UIImage(color: selectedButtonBackground), for: .selected)
        }
    }
}

extension EmojiMoodPickerView {
    // Note: Order matters for CaseIterable
    // Button order determined by declaration order
    enum Mood: CaseIterable {
        case thrilled
        case happy
        case inconvenienced
        case disappointed
        case angry

        var emojiRepresentation: String {
            switch self {
            case .thrilled: return Emoji.smiley.rawValue
            case .happy: return Emoji.slightlySmilingFace.rawValue
            case .inconvenienced: return Emoji.neutralFace.rawValue
            case .disappointed: return Emoji.slightlyFrowningFace.rawValue
            case .angry: return Emoji.angry.rawValue
            }
        }

        var stringRepresentation: String {
            switch self {
            case .thrilled: return "emoji_5"
            case .happy: return "emoji_4"
            case .inconvenienced: return "emoji_3"
            case .disappointed: return "emoji_2"
            case .angry: return "emoji_1"
            }
        }
    }
}

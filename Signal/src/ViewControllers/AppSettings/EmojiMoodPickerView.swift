//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class EmojiMoodPickerView: UIView {

    // MARK: - Properties

    var selectedMood: Mood? {
        didSet {
            moodButtons.forEach { (mood, button) in
                button.isSelected = (mood == selectedMood)
            }
        }
    }

    private let moodButtons: [Mood: UIButton] = Mood.allCases.dictionaryWithValues { (mood) in
        let button = UIButton(type: .custom)
        let title = NSAttributedString(string: "\(mood.rawValue)", attributes: [
            .font: UIFont.boldSystemFont(ofSize: 24)
        ])
        button.clipsToBounds = true
        button.setAttributedTitle(title, for: .normal)
        return button
    }

    private let buttonStack: UIStackView = {
        let stackView = UIStackView(forAutoLayout: ())
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .fill
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme() {
        let defaultButtonBackground = Theme.isDarkThemeEnabled ? UIColor.ows_gray80 : UIColor.ows_gray05
        let selectedButtonBackground = Theme.isDarkThemeEnabled ? Theme.accentBlueColor : UIColor(rgbHex: 0x4490e3)

        moodButtons.values.forEach { (button) in
            button.setBackgroundImage(UIImage(color: defaultButtonBackground), for: .normal)
            button.setBackgroundImage(UIImage(color: selectedButtonBackground), for: .selected)
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        // Am I not understanding the contract here? The stackview has correct bounds at this
        // point but the component buttons all have bounds of .zero
        // Working around this by dispatching for later...
        DispatchQueue.main.async {
            // The button sizes shouldn't change, but if they do we should update the
            // the corner radius for the new bounds
            for button in self.moodButtons.values {
                let smallerAxis = button.bounds.size.smallerAxis
                button.layer.cornerRadius = (smallerAxis / 2)
            }
        }
    }

    // MARK: - Button responder

    @objc func buttonWasTapped(_ button: UIButton) {
        // When this action is invoked, our selection state hasn't been updated yet
        // If we were not selected, we're being selected
        // If we were selected, we're being unselected
        let isBeingSelected = !button.isSelected
        selectedMood = isBeingSelected ? mood(for: button) : nil
    }

    private func mood(for button: UIButton) -> Mood? {
        moodButtons.first(where: { $1 == button })?.key
    }
}

extension EmojiMoodPickerView {
    // Note: Order matters for CaseIterable
    // Button order determined by declaration order
    enum Mood: Character, CaseIterable {
        case thrilled = "😃"
        case happy = "🙂"
        case inconvenienced = "😐"
        case disappointed = "🙁"
        case angry = "😠"

        var rawStringVal: String {
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

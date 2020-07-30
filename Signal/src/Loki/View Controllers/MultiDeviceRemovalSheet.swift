import PromiseKit

final class MultiDeviceRemovalSheet : Sheet {

    private lazy var removalDate: Date = {
        let calendar = Calendar(identifier: .gregorian)
        let timezone = TimeZone(identifier: "Australia/Melbourne")
        let components = DateComponents(calendar: calendar, timeZone: timezone, year: 2020, month: 8, day: 6, hour: 17)
        return calendar.date(from: components)!
    }()

    private lazy var removalDateDescription: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: removalDate)
    }()

    private lazy var explanation: String = {
        if UserDefaults.standard[.masterHexEncodedPublicKey] != nil {
            let format = """
            You’re seeing this because this is a secondary device in a multi-device setup. To improve reliability and stability, we’ve decided to temporarily disable Session’s multi-device functionality on %@. Device linking has been disabled, and the next update will erase existing secondary devices.

            To read more about this change, visit the Session FAQ at getsession.org/faq.
            """
            return String(format: format, removalDateDescription)
        } else {
            let format = """
            You’re seeing this because you have a secondary device linked to your Session ID. To improve reliability and stability, we’ve decided to temporarily disable Session’s multi-device functionality on %@. Device linking has been disabled, and the next update will erase existing secondary devices.

            To read more about this change, visit the Session FAQ at getsession.org/faq
            """
            return String(format: format, removalDateDescription)
        }
    }()

    private lazy var attributedExplanation: NSAttributedString = {
        let result = NSMutableAttributedString(string: explanation)
        result.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: Values.smallFontSize), range: (explanation as NSString).range(of: removalDateDescription))
        result.addAttribute(.foregroundColor, value: Colors.accent, range: (explanation as NSString).range(of: removalDateDescription))
        result.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: Values.smallFontSize), range: (explanation as NSString).range(of: "getsession.org/faq"))
        result.addAttribute(.foregroundColor, value: Colors.accent, range: (explanation as NSString).range(of: "getsession.org/faq"))
        return result
    }()

    private lazy var explanationLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.attributedText = attributedExplanation
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        return result
    }()

    override func populateContentView() {
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: isIPhone5OrSmaller ? Values.largeFontSize : Values.veryLargeFontSize)
        titleLabel.text = "Changes to Multi-Device"
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        // Set up explanation label
        explanationLabel.isUserInteractionEnabled = true
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleExplanationLabelTapped))
        explanationLabel.addGestureRecognizer(tapGestureRecognizer)
        // Set up OK button
        let okButton = Button(style: .prominentOutline, size: .large)
        okButton.set(.width, to: 240)
        okButton.setTitle(NSLocalizedString("OK", comment: ""), for: UIControl.State.normal)
        okButton.addTarget(self, action: #selector(close), for: UIControl.Event.touchUpInside)
        // Set up main stack view
        let stackView = UIStackView(arrangedSubviews: [ titleLabel, explanationLabel, okButton ])
        stackView.axis = .vertical
        stackView.spacing = Values.veryLargeSpacing
        stackView.alignment = .center
        // Set up constraints
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: Values.veryLargeSpacing)
        stackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.veryLargeSpacing)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: Values.veryLargeSpacing + overshoot)
    }

    @objc private func handleExplanationLabelTapped(_ tapGestureRecognizer: UITapGestureRecognizer) {
        let range = (explanationLabel.text! as NSString).range(of: "getsession.org/faq")
        let touchInExplanationLabelCoordinates = tapGestureRecognizer.location(in: explanationLabel)
        let characterIndex = explanationLabel.characterIndex(for: touchInExplanationLabelCoordinates)
        guard range.contains(characterIndex) else { return }
        let url = URL(string: "https://getsession.org/faq")!
        UIApplication.shared.open(url)
    }
}

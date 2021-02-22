import UIKit

final class OptionView : UIView {
    private let title: String
    private let explanation: String
    private let delegate: OptionViewDelegate
    private let isRecommended: Bool
    var isSelected = false { didSet { handleIsSelectedChanged() } }

    private static let cornerRadius: CGFloat = 8
    
    init(title: String, explanation: String, delegate: OptionViewDelegate, isRecommended: Bool = false) {
        self.title = title
        self.explanation = explanation
        self.delegate = delegate
        self.isRecommended = isRecommended
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }

    override init(frame: CGRect) {
        preconditionFailure("Use init(string:explanation:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(string:explanation:) instead.")
    }

    private func setUpViewHierarchy() {
        backgroundColor = Colors.pnOptionBackground
        // Round corners
        layer.cornerRadius = OptionView.cornerRadius
        // Set up border
        layer.borderWidth = 1
        layer.borderColor = Colors.pnOptionBorder.cgColor
        // Set up shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 0.8)
        layer.shadowOpacity = isLightMode ? 0.16 : 1
        layer.shadowRadius = isLightMode ? 4 : 6
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = title
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        explanationLabel.text = explanation
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up stack view
        let stackView = UIStackView(arrangedSubviews: [ titleLabel, explanationLabel ])
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.alignment = .fill
        addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: self, withInset: 12)
        stackView.pin(.top, to: .top, of: self, withInset: 12)
        self.pin(.trailing, to: .trailing, of: stackView, withInset: 12)
        self.pin(.bottom, to: .bottom, of: stackView, withInset: 12)
        // Set up recommended label if needed
        if isRecommended {
            let recommendedLabel = UILabel()
            recommendedLabel.textColor = Colors.accent
            recommendedLabel.font = .boldSystemFont(ofSize: Values.smallFontSize)
            recommendedLabel.text = NSLocalizedString("vc_pn_mode_recommended_option_tag", comment: "")
            stackView.addArrangedSubview(recommendedLabel)
        }
        // Set up tap gesture recognizer
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGestureRecognizer)
    }

    @objc private func handleTap() {
        isSelected = !isSelected
    }

    private func handleIsSelectedChanged() {
        let animationDuration: TimeInterval = 0.25
        // Animate border color
        let newBorderColor = isSelected ? Colors.accent.cgColor : Colors.pnOptionBorder.cgColor
        let borderAnimation = CABasicAnimation(keyPath: "borderColor")
        borderAnimation.fromValue = layer.shadowColor
        borderAnimation.toValue = newBorderColor
        borderAnimation.duration = animationDuration
        layer.add(borderAnimation, forKey: borderAnimation.keyPath)
        layer.borderColor = newBorderColor
        // Animate shadow color
        let newShadowColor = isSelected ? Colors.expandedButtonGlowColor.cgColor : UIColor.black.cgColor
        let shadowAnimation = CABasicAnimation(keyPath: "shadowColor")
        shadowAnimation.fromValue = layer.shadowColor
        shadowAnimation.toValue = newShadowColor
        shadowAnimation.duration = animationDuration
        layer.add(shadowAnimation, forKey: shadowAnimation.keyPath)
        layer.shadowColor = newShadowColor
        // Notify delegate
        if isSelected { delegate.optionViewDidActivate(self) }
    }
}

// MARK: Option View Delegate
protocol OptionViewDelegate {

    func optionViewDidActivate(_ optionView: OptionView)
}

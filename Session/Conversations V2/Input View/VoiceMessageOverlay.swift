
final class VoiceMessageOverlay : UIView {
    private let voiceMessageButtonFrame: CGRect
    private lazy var slideToCancelStackViewRightConstraint = slideToCancelStackView.pin(.right, to: .right, of: self)
    private lazy var slideToCancelStackViewCenterHorizontalConstraint = slideToCancelStackView.center(.horizontal, in: self)

    // MARK: UI Components
    private lazy var slideToCancelStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .horizontal
        result.spacing = Values.smallSpacing
        result.alpha = 0
        result.alignment = .center
        return result
    }()

    private lazy var durationStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .horizontal
        result.spacing = 4
        result.alpha = 0
        result.alignment = .center
        return result
    }()

    private lazy var durationLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.destructive
        result.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.text = "00:12"
        return result
    }()

    // MARK: Settings
    private static let circleSize: CGFloat = 100
    private static let iconSize: CGFloat = 28
    private static let chevronSize: CGFloat = 20

    // MARK: Lifecycle
    init(voiceMessageButtonFrame: CGRect) {
        self.voiceMessageButtonFrame = voiceMessageButtonFrame
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }

    override init(frame: CGRect) {
        preconditionFailure("Use init(voiceMessageButtonFrame:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(voiceMessageButtonFrame:) instead.")
    }

    private func setUpViewHierarchy() {
        let iconSize = VoiceMessageOverlay.iconSize
        // Icon
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(named: "Microphone")!.withTint(.white)
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.set(.width, to: iconSize)
        iconImageView.set(.height, to: iconSize)
        addSubview(iconImageView)
        let voiceMessageButtonCenter = voiceMessageButtonFrame.center
        iconImageView.pin(.left, to: .left, of: self, withInset: voiceMessageButtonCenter.x - iconSize / 2)
        iconImageView.pin(.top, to: .top, of: self, withInset: voiceMessageButtonCenter.y - iconSize / 2)
        // Circle
        let circleView = UIView()
        circleView.backgroundColor = Colors.destructive
        let circleSize = VoiceMessageOverlay.circleSize
        circleView.set(.width, to: circleSize)
        circleView.set(.height, to: circleSize)
        circleView.layer.cornerRadius = circleSize / 2
        circleView.layer.masksToBounds = true
        insertSubview(circleView, at: 0)
        circleView.center(in: iconImageView)
        // Slide to cancel stack view
        let chevronSize = VoiceMessageOverlay.chevronSize
        let chevronLeft1 = UIImageView(image: UIImage(named: "small_chevron_left")!.withTint(Colors.destructive))
        chevronLeft1.contentMode = .scaleAspectFit
        chevronLeft1.set(.width, to: chevronSize)
        chevronLeft1.set(.height, to: chevronSize)
        slideToCancelStackView.addArrangedSubview(chevronLeft1)
        let slideToCancelLabel = UILabel()
        slideToCancelLabel.text = "Slide to cancel"
        slideToCancelLabel.font = .boldSystemFont(ofSize: Values.smallFontSize)
        slideToCancelLabel.textColor = Colors.destructive
        slideToCancelStackView.addArrangedSubview(slideToCancelLabel)
        let chevronLeft2 = UIImageView(image: UIImage(named: "small_chevron_left")!.withTint(Colors.destructive))
        chevronLeft2.contentMode = .scaleAspectFit
        chevronLeft2.set(.width, to: chevronSize)
        chevronLeft2.set(.height, to: chevronSize)
        slideToCancelStackView.addArrangedSubview(chevronLeft2)
        addSubview(slideToCancelStackView)
        slideToCancelStackViewRightConstraint.isActive = true
        slideToCancelStackView.center(.vertical, in: iconImageView)
        // Duration stack view
        let microphoneImageView = UIImageView()
        microphoneImageView.image = UIImage(named: "Microphone")!.withTint(Colors.destructive)
        microphoneImageView.contentMode = .scaleAspectFit
        microphoneImageView.set(.width, to: iconSize)
        microphoneImageView.set(.height, to: iconSize)
        durationStackView.addArrangedSubview(microphoneImageView)
        durationStackView.addArrangedSubview(durationLabel)
        addSubview(durationStackView)
        durationStackView.pin(.left, to: .left, of: self, withInset: Values.largeSpacing)
        durationStackView.center(.vertical, in: iconImageView)
    }

    // MARK: Animation
    func animate() {
        UIView.animate(withDuration: 0.15, animations: {
            self.alpha = 1
        }, completion: { _ in
            self.slideToCancelStackViewRightConstraint.isActive = false
            self.slideToCancelStackViewCenterHorizontalConstraint.isActive = true
            UIView.animate(withDuration: 0.15) {
                self.slideToCancelStackView.alpha = 1
                self.durationStackView.alpha = 1
                self.layoutIfNeeded()
            }
        })
    }
}

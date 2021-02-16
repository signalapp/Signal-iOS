
final class VoiceMessageRecordingView : UIView {
    private let voiceMessageButtonFrame: CGRect
    private lazy var slideToCancelStackViewRightConstraint = slideToCancelStackView.pin(.right, to: .right, of: self)
    private lazy var slideToCancelLabelCenterHorizontalConstraint = slideToCancelLabel.center(.horizontal, in: self)
    private lazy var pulseViewWidthConstraint = pulseView.set(.width, to: VoiceMessageRecordingView.circleSize)
    private lazy var pulseViewHeightConstraint = pulseView.set(.height, to: VoiceMessageRecordingView.circleSize)
    private lazy var lockViewBottomConstraint = lockView.pin(.bottom, to: .top, of: self, withInset: Values.mediumSpacing)
    private let recordingStartDate = Date()
    private var recordingTimer: Timer?

    // MARK: UI Components
    private lazy var pulseView: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.destructive
        result.layer.cornerRadius = VoiceMessageRecordingView.circleSize / 2
        result.layer.masksToBounds = true
        result.alpha = 0.5
        return result
    }()

    private lazy var slideToCancelStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .horizontal
        result.spacing = Values.smallSpacing
        result.alignment = .center
        return result
    }()

    private lazy var slideToCancelLabel: UILabel = {
        let result = UILabel()
        result.text = "Slide to cancel"
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.textColor = Colors.text.withAlphaComponent(Values.mediumOpacity)
        return result
    }()

    private lazy var durationStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .horizontal
        result.spacing = Values.smallSpacing
        result.alignment = .center
        return result
    }()

    private lazy var dotView: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.destructive
        let dotSize = VoiceMessageRecordingView.dotSize
        result.set(.width, to: dotSize)
        result.set(.height, to: dotSize)
        result.layer.cornerRadius = dotSize / 2
        result.layer.masksToBounds = true
        return result
    }()

    private lazy var durationLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.text = "00:00"
        return result
    }()

    private lazy var lockView = LockView()

    // MARK: Settings
    private static let circleSize: CGFloat = 96
    private static let pulseSize: CGFloat = 24
    private static let microPhoneIconSize: CGFloat = 28
    private static let chevronSize: CGFloat = 16
    private static let dotSize: CGFloat = 16

    // MARK: Lifecycle
    init(voiceMessageButtonFrame: CGRect) {
        self.voiceMessageButtonFrame = voiceMessageButtonFrame
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateDurationLabel()
        }
    }

    override init(frame: CGRect) {
        preconditionFailure("Use init(voiceMessageButtonFrame:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(voiceMessageButtonFrame:) instead.")
    }

    deinit {
        recordingTimer?.invalidate()
    }

    private func setUpViewHierarchy() {
        // Icon
        let iconSize = VoiceMessageRecordingView.microPhoneIconSize
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
        let circleSize = VoiceMessageRecordingView.circleSize
        circleView.set(.width, to: circleSize)
        circleView.set(.height, to: circleSize)
        circleView.layer.cornerRadius = circleSize / 2
        circleView.layer.masksToBounds = true
        insertSubview(circleView, at: 0)
        circleView.center(in: iconImageView)
        // Pulse
        insertSubview(pulseView, at: 0)
        pulseView.center(in: circleView)
        // Slide to cancel stack view
        let chevronSize = VoiceMessageRecordingView.chevronSize
        let chevronColor = (isLightMode ? UIColor.black : UIColor.white).withAlphaComponent(Values.mediumOpacity)
        let chevronImageView = UIImageView(image: UIImage(named: "small_chevron_left")!.withTint(chevronColor))
        chevronImageView.contentMode = .scaleAspectFit
        chevronImageView.set(.width, to: chevronSize)
        chevronImageView.set(.height, to: chevronSize)
        slideToCancelStackView.addArrangedSubview(chevronImageView)
        slideToCancelStackView.addArrangedSubview(slideToCancelLabel)
        addSubview(slideToCancelStackView)
        slideToCancelStackViewRightConstraint.isActive = true
        slideToCancelStackView.center(.vertical, in: iconImageView)
        // Duration stack view
        durationStackView.addArrangedSubview(dotView)
        durationStackView.addArrangedSubview(durationLabel)
        addSubview(durationStackView)
        durationStackView.pin(.left, to: .left, of: self, withInset: Values.largeSpacing)
        durationStackView.center(.vertical, in: iconImageView)
        // Lock view
        addSubview(lockView)
        lockView.center(.horizontal, in: iconImageView)
        lockViewBottomConstraint.isActive = true
    }

    // MARK: Updating
    @objc private func updateDurationLabel() {
        let interval = Date().timeIntervalSince(recordingStartDate)
        durationLabel.text = OWSFormat.formatDurationSeconds(Int(interval))
    }

    // MARK: Animation
    func animate() {
        layoutIfNeeded()
        slideToCancelStackViewRightConstraint.isActive = false
        slideToCancelLabelCenterHorizontalConstraint.isActive = true
        lockViewBottomConstraint.constant = -Values.mediumSpacing
        UIView.animate(withDuration: 0.25, animations: { [weak self] in
            guard let self = self else { return }
            self.alpha = 1
            self.layoutIfNeeded()
        }, completion: { [weak self] _ in
            guard let self = self else { return }
            self.fadeOutDotView()
            self.pulse()
        })
    }

    private func fadeOutDotView() {
        UIView.animate(withDuration: 0.5, animations: { [weak self] in
            self?.dotView.alpha = 0
        }, completion: { [weak self] _ in
            self?.fadeInDotView()
        })
    }

    private func fadeInDotView() {
        UIView.animate(withDuration: 0.5, animations: { [weak self] in
            self?.dotView.alpha = 1
        }, completion: { [weak self] _ in
            self?.fadeOutDotView()
        })
    }

    private func pulse() {
        let collapsedSize = VoiceMessageRecordingView.circleSize
        let collapsedFrame = CGRect(center: pulseView.center, size: CGSize(width: collapsedSize, height: collapsedSize))
        let expandedSize = VoiceMessageRecordingView.circleSize + VoiceMessageRecordingView.pulseSize
        let expandedFrame = CGRect(center: pulseView.center, size: CGSize(width: expandedSize, height: expandedSize))
        pulseViewWidthConstraint.constant = expandedSize
        pulseViewHeightConstraint.constant = expandedSize
        UIView.animate(withDuration: 1, animations: { [weak self] in
            guard let self = self else { return }
            self.layoutIfNeeded()
            self.pulseView.frame = expandedFrame
            self.pulseView.layer.cornerRadius = expandedSize / 2
            self.pulseView.alpha = 0
        }, completion: { [weak self] _ in
            guard let self = self else { return }
            self.pulseViewWidthConstraint.constant = collapsedSize
            self.pulseViewHeightConstraint.constant = collapsedSize
            self.pulseView.frame = collapsedFrame
            self.pulseView.layer.cornerRadius = collapsedSize / 2
            self.pulseView.alpha = 0.5
            self.pulse()
        })
    }
}

// MARK: Lock View
extension VoiceMessageRecordingView {

    fileprivate final class LockView : UIView {

        private static let width: CGFloat = 44
        private static let lockIconSize: CGFloat = 20
        private static let chevronIconSize: CGFloat = 20

        override init(frame: CGRect) {
            super.init(frame: frame)
            setUpViewHierarchy()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setUpViewHierarchy()
        }

        private func setUpViewHierarchy() {
            let iconTint: UIColor = isLightMode ? .black : .white
            // Background & blur
            let backgroundView = UIView()
            backgroundView.backgroundColor = isLightMode ? .white : .black
            backgroundView.alpha = Values.lowOpacity
            addSubview(backgroundView)
            backgroundView.pin(to: self)
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
            addSubview(blurView)
            blurView.pin(to: self)
            // Size & shape
            let width = LockView.width
            set(.width, to: width)
            layer.cornerRadius = width / 2
            layer.masksToBounds = true
            // Border
            layer.borderWidth = 1
            let borderColor = (isLightMode ? UIColor.black : UIColor.white).withAlphaComponent(Values.veryLowOpacity)
            layer.borderColor = borderColor.cgColor
            // Lock icon
            let lockIconImageView = UIImageView(image: UIImage(named: "ic_lock_outline")!.withTint(iconTint))
            let lockIconSize = LockView.lockIconSize
            lockIconImageView.set(.width, to: lockIconSize)
            lockIconImageView.set(.height, to: lockIconSize)
            // Chevron icon
            let chevronIconImageView = UIImageView(image: UIImage(named: "ic_chevron_up")!.withTint(iconTint))
            let chevronIconSize = LockView.chevronIconSize
            chevronIconImageView.set(.width, to: chevronIconSize)
            chevronIconImageView.set(.height, to: chevronIconSize)
            // Stack view
            let stackView = UIStackView(arrangedSubviews: [ lockIconImageView, chevronIconImageView ])
            stackView.axis = .vertical
            stackView.spacing = Values.smallSpacing
            stackView.alignment = .center
            stackView.isLayoutMarginsRelativeArrangement = true
            stackView.layoutMargins = UIEdgeInsets(top: 12, leading: 0, bottom: 8, trailing: 0)
            addSubview(stackView)
            stackView.pin(to: self)
        }
    }
}


final class VoiceMessageRecordingView : UIView {
    private let voiceMessageButtonFrame: CGRect
    private weak var delegate: VoiceMessageRecordingViewDelegate?
    private lazy var slideToCancelStackViewRightConstraint = slideToCancelStackView.pin(.right, to: .right, of: self)
    private lazy var slideToCancelLabelCenterHorizontalConstraint = slideToCancelLabel.center(.horizontal, in: self)
    private lazy var pulseViewWidthConstraint = pulseView.set(.width, to: VoiceMessageRecordingView.circleSize)
    private lazy var pulseViewHeightConstraint = pulseView.set(.height, to: VoiceMessageRecordingView.circleSize)
    private lazy var lockViewBottomConstraint = lockView.pin(.bottom, to: .top, of: self, withInset: Values.mediumSpacing)
    private let recordingStartDate = Date()
    private var recordingTimer: Timer?

    // MARK: UI Components
    private lazy var iconImageView: UIImageView = {
        let result = UIImageView()
        result.image = UIImage(named: "Microphone")!.withTint(.white)
        result.contentMode = .scaleAspectFit
        let size = VoiceMessageRecordingView.iconSize
        result.set(.width, to: size)
        result.set(.height, to: size)
        return result
    }()

    private lazy var circleView: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.destructive
        let size = VoiceMessageRecordingView.circleSize
        result.set(.width, to: size)
        result.set(.height, to: size)
        result.layer.cornerRadius = size / 2
        result.layer.masksToBounds = true
        return result
    }()

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

    private lazy var chevronImageView: UIImageView = {
        let chevronSize = VoiceMessageRecordingView.chevronSize
        let chevronColor = (isLightMode ? UIColor.black : UIColor.white).withAlphaComponent(Values.mediumOpacity)
        let result = UIImageView(image: UIImage(named: "small_chevron_left")!.withTint(chevronColor))
        result.contentMode = .scaleAspectFit
        result.set(.width, to: chevronSize)
        result.set(.height, to: chevronSize)
        return result
    }()

    private lazy var slideToCancelLabel: UILabel = {
        let result = UILabel()
        result.text = NSLocalizedString("vc_conversation_voice_message_cancel_message", comment: "")
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.textColor = Colors.text.withAlphaComponent(Values.mediumOpacity)
        return result
    }()

    private lazy var cancelButton: UIButton = {
        let result = UIButton()
        result.setTitle("Cancel", for: UIControl.State.normal)
        result.titleLabel!.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.setTitleColor(Colors.text, for: UIControl.State.normal)
        result.addTarget(self, action: #selector(handleCancelButtonTapped), for: UIControl.Event.touchUpInside)
        result.alpha = 0
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
        result.text = "0:00"
        return result
    }()

    private lazy var lockView = LockView()

    // MARK: Settings
    private static let circleSize: CGFloat = 96
    private static let pulseSize: CGFloat = 24
    private static let iconSize: CGFloat = 28
    private static let chevronSize: CGFloat = 16
    private static let dotSize: CGFloat = 16
    private static let lockViewHitMargin: CGFloat = 40

    // MARK: Lifecycle
    init(voiceMessageButtonFrame: CGRect, delegate: VoiceMessageRecordingViewDelegate?) {
        self.voiceMessageButtonFrame = voiceMessageButtonFrame
        self.delegate = delegate
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
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
        let iconSize = VoiceMessageRecordingView.iconSize
        addSubview(iconImageView)
        let voiceMessageButtonCenter = voiceMessageButtonFrame.center
        iconImageView.pin(.left, to: .left, of: self, withInset: voiceMessageButtonCenter.x - iconSize / 2)
        iconImageView.pin(.top, to: .top, of: self, withInset: voiceMessageButtonCenter.y - iconSize / 2)
        // Circle
        insertSubview(circleView, at: 0)
        circleView.center(in: iconImageView)
        // Pulse
        insertSubview(pulseView, at: 0)
        pulseView.center(in: circleView)
        // Slide to cancel stack view
        slideToCancelStackView.addArrangedSubview(chevronImageView)
        slideToCancelStackView.addArrangedSubview(slideToCancelLabel)
        addSubview(slideToCancelStackView)
        slideToCancelStackViewRightConstraint.isActive = true
        slideToCancelStackView.center(.vertical, in: iconImageView)
        // Cancel button
        addSubview(cancelButton)
        cancelButton.center(.horizontal, in: self)
        cancelButton.center(.vertical, in: iconImageView)
        // Duration stack view
        durationStackView.addArrangedSubview(dotView)
        durationStackView.addArrangedSubview(durationLabel)
        addSubview(durationStackView)
        durationStackView.pin(.left, to: .left, of: self, withInset: Values.largeSpacing)
        durationStackView.center(.vertical, in: iconImageView)
        // Lock view
        addSubview(lockView)
        lockView.centerXAnchor.constraint(equalTo: iconImageView.centerXAnchor, constant: 2).isActive = true
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

    // MARK: Interaction
    func handleLongPressMoved(to location: CGPoint) {
        if location.x < bounds.center.x {
            let translationX = location.x - bounds.center.x
            let sign: CGFloat = -1
            let chevronDamping: CGFloat = 4
            let labelDamping: CGFloat = 3
            let chevronX = (chevronDamping * (sqrt(abs(translationX)) / sqrt(chevronDamping))) * sign
            let labelX = (labelDamping * (sqrt(abs(translationX)) / sqrt(labelDamping))) * sign
            chevronImageView.transform = CGAffineTransform(translationX: chevronX, y: 0)
            slideToCancelLabel.transform = CGAffineTransform(translationX: labelX, y: 0)
        } else {
            chevronImageView.transform = .identity
            slideToCancelLabel.transform = .identity
        }
        if isValidLockViewLocation(location) {
            if !lockView.isExpanded {
                UIView.animate(withDuration: 0.25) {
                    self.lockViewBottomConstraint.constant = -Values.mediumSpacing + LockView.expansionMargin
                }
            }
            lockView.expandIfNeeded()
        } else {
            if lockView.isExpanded {
                UIView.animate(withDuration: 0.25) {
                    self.lockViewBottomConstraint.constant = -Values.mediumSpacing
                }
            }
            lockView.collapseIfNeeded()
        }
    }

    func handleLongPressEnded(at location: CGPoint) {
        if pulseView.frame.contains(location) {
            delegate?.endVoiceMessageRecording()
        } else if isValidLockViewLocation(location) {
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleCircleViewTap))
            circleView.addGestureRecognizer(tapGestureRecognizer)
            UIView.animate(withDuration: 0.25, delay: 0, options: .transitionCrossDissolve, animations: {
                self.lockView.alpha = 0
                self.iconImageView.image = UIImage(named: "ArrowUp")!.withTint(.white)
                self.slideToCancelStackView.alpha = 0
                self.cancelButton.alpha = 1
            }, completion: { _ in
                // Do nothing
            })
        } else {
            delegate?.cancelVoiceMessageRecording()
        }
    }

    @objc private func handleCircleViewTap() {
        delegate?.endVoiceMessageRecording()
    }

    @objc private func handleCancelButtonTapped() {
        delegate?.cancelVoiceMessageRecording()
    }

    // MARK: Convenience
    private func isValidLockViewLocation(_ location: CGPoint) -> Bool {
        let lockViewHitMargin = VoiceMessageRecordingView.lockViewHitMargin
        return location.y < 0 && location.x > (lockView.frame.minX - lockViewHitMargin) && location.x < (lockView.frame.maxX + lockViewHitMargin)
    }
}

// MARK: Lock View
extension VoiceMessageRecordingView {

    fileprivate final class LockView : UIView {
        private lazy var widthConstraint = set(.width, to: LockView.width)
        private(set) var isExpanded = false

        private lazy var stackView: UIStackView = {
            let result = UIStackView()
            result.axis = .vertical
            result.spacing = Values.smallSpacing
            result.alignment = .center
            result.isLayoutMarginsRelativeArrangement = true
            result.layoutMargins = UIEdgeInsets(top: 12, leading: 0, bottom: 8, trailing: 0)
            return result
        }()

        private static let width: CGFloat = 44
        static let expansionMargin: CGFloat = 3
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
            widthConstraint.isActive = true
            layer.cornerRadius = LockView.width / 2
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
            stackView.addArrangedSubview(lockIconImageView)
            // Chevron icon
            let chevronIconImageView = UIImageView(image: UIImage(named: "ic_chevron_up")!.withTint(iconTint))
            let chevronIconSize = LockView.chevronIconSize
            chevronIconImageView.set(.width, to: chevronIconSize)
            chevronIconImageView.set(.height, to: chevronIconSize)
            stackView.addArrangedSubview(chevronIconImageView)
            // Stack view
            addSubview(stackView)
            stackView.pin(to: self)
        }

        func expandIfNeeded() {
            guard !isExpanded else { return }
            isExpanded = true
            let expansionMargin = LockView.expansionMargin
            let newWidth = LockView.width + 2 * expansionMargin
            widthConstraint.constant = newWidth
            UIView.animate(withDuration: 0.25) {
                self.layer.cornerRadius = newWidth / 2
                self.stackView.layoutMargins = UIEdgeInsets(top: 12 + expansionMargin, leading: 0, bottom: 8 + expansionMargin, trailing: 0)
                self.layoutIfNeeded()
            }
        }

        func collapseIfNeeded() {
            guard isExpanded else { return }
            isExpanded = false
            let newWidth = LockView.width
            widthConstraint.constant = newWidth
            UIView.animate(withDuration: 0.25) {
                self.layer.cornerRadius = newWidth / 2
                self.stackView.layoutMargins = UIEdgeInsets(top: 12, leading: 0, bottom: 8, trailing: 0)
                self.layoutIfNeeded()
            }
        }
    }
}

// MARK: - Delegate

protocol VoiceMessageRecordingViewDelegate: AnyObject {
    func startVoiceMessageRecording()
    func endVoiceMessageRecording()
    func cancelVoiceMessageRecording()
}

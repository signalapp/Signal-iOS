import NVActivityIndicatorView

@objc(SNVoiceMessageView)
public final class VoiceMessageView : UIView {
    private let viewItem: ConversationViewItem
    private var isShowingSpeedUpLabel = false
    @objc var progress: Int = 0 { didSet { handleProgressChanged() } }
    @objc var isPlaying = false { didSet { handleIsPlayingChanged() } }

    private lazy var progressViewRightConstraint = progressView.pin(.right, to: .right, of: self, withInset: -VoiceMessageView.width)

    private var attachment: TSAttachment? { viewItem.attachmentStream ?? viewItem.attachmentPointer }
    private var duration: Int { Int(viewItem.audioDurationSeconds) }

    // MARK: UI Components
    private lazy var progressView: UIView = {
        let result = UIView()
        result.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        return result
    }()

    private lazy var toggleImageView: UIImageView = {
        let result = UIImageView(image: UIImage(named: "Play"))
        result.set(.width, to: 8)
        result.set(.height, to: 8)
        result.contentMode = .scaleAspectFit
        return result
    }()

    private lazy var loader: NVActivityIndicatorView = {
        let result = NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: Colors.text, padding: nil)
        result.set(.width, to: VoiceMessageView.toggleContainerSize + 2)
        result.set(.height, to: VoiceMessageView.toggleContainerSize + 2)
        return result
    }()

    private lazy var countdownLabelContainer: UIView = {
        let result = UIView()
        result.backgroundColor = .white
        result.layer.masksToBounds = true
        result.set(.height, to: VoiceMessageView.toggleContainerSize)
        result.set(.width, to: 44)
        return result
    }()

    private lazy var countdownLabel: UILabel = {
        let result = UILabel()
        result.textColor = .black
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.text = "0:00"
        return result
    }()

    private lazy var speedUpLabel: UILabel = {
        let result = UILabel()
        result.textColor = .black
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.alpha = 0
        result.text = "1.5x"
        result.textAlignment = .center
        return result
    }()

    // MARK: Settings
    private static let width: CGFloat = 160
    private static let toggleContainerSize: CGFloat = 20
    private static let inset = Values.smallSpacing

    // MARK: Lifecycle
    init(viewItem: ConversationViewItem) {
        self.viewItem = viewItem
        self.progress = Int(viewItem.audioProgressSeconds)
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
        handleProgressChanged()
    }

    override init(frame: CGRect) {
        preconditionFailure("Use init(viewItem:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(viewItem:) instead.")
    }

    private func setUpViewHierarchy() {
        let toggleContainerSize = VoiceMessageView.toggleContainerSize
        let inset = VoiceMessageView.inset
        // Width & height
        set(.width, to: VoiceMessageView.width)
        // Toggle
        let toggleContainer = UIView()
        toggleContainer.backgroundColor = .white
        toggleContainer.set(.width, to: toggleContainerSize)
        toggleContainer.set(.height, to: toggleContainerSize)
        toggleContainer.addSubview(toggleImageView)
        toggleImageView.center(in: toggleContainer)
        toggleContainer.layer.cornerRadius = toggleContainerSize / 2
        toggleContainer.layer.masksToBounds = true
        // Line
        let lineView = UIView()
        lineView.backgroundColor = .white
        lineView.set(.height, to: 1)
        // Countdown label
        countdownLabelContainer.addSubview(countdownLabel)
        countdownLabel.center(in: countdownLabelContainer)
        // Speed up label
        countdownLabelContainer.addSubview(speedUpLabel)
        speedUpLabel.center(in: countdownLabelContainer)
        // Constraints
        addSubview(progressView)
        progressView.pin(.left, to: .left, of: self)
        progressView.pin(.top, to: .top, of: self)
        progressViewRightConstraint.isActive = true
        progressView.pin(.bottom, to: .bottom, of: self)
        addSubview(toggleContainer)
        toggleContainer.pin(.left, to: .left, of: self, withInset: inset)
        toggleContainer.pin(.top, to: .top, of: self, withInset: inset)
        toggleContainer.pin(.bottom, to: .bottom, of: self, withInset: -inset)
        addSubview(lineView)
        lineView.pin(.left, to: .right, of: toggleContainer)
        lineView.center(.vertical, in: self)
        addSubview(countdownLabelContainer)
        countdownLabelContainer.pin(.left, to: .right, of: lineView)
        countdownLabelContainer.pin(.right, to: .right, of: self, withInset: -inset)
        countdownLabelContainer.center(.vertical, in: self)
        addSubview(loader)
        loader.center(in: toggleContainer)
    }

    // MARK: Updating
    public override func layoutSubviews() {
        super.layoutSubviews()
        countdownLabelContainer.layer.cornerRadius = countdownLabelContainer.bounds.height / 2
    }

    private func handleIsPlayingChanged() {
        toggleImageView.image = isPlaying ? UIImage(named: "Pause") : UIImage(named: "Play")
        if !isPlaying { progress = 0 }
    }

    private func handleProgressChanged() {
        let isDownloaded = (attachment?.isDownloaded == true)
        loader.isHidden = isDownloaded
        if isDownloaded { loader.stopAnimating() } else if !loader.isAnimating { loader.startAnimating() }
        guard isDownloaded else { return }
        countdownLabel.text = OWSFormat.formatDurationSeconds(duration - progress)
        guard viewItem.audioProgressSeconds > 0 && viewItem.audioDurationSeconds > 0 else {
            return progressViewRightConstraint.constant = -VoiceMessageView.width
        }
        let fraction = viewItem.audioProgressSeconds / viewItem.audioDurationSeconds
        progressViewRightConstraint.constant = -(VoiceMessageView.width * (1 - fraction))
    }

    func showSpeedUpLabel() {
        guard !isShowingSpeedUpLabel else { return }
        isShowingSpeedUpLabel = true
        UIView.animate(withDuration: 0.25) { [weak self] in
            guard let self = self else { return }
            self.countdownLabel.alpha = 0
            self.speedUpLabel.alpha = 1
        }
        Timer.scheduledTimer(withTimeInterval: 1.25, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.25, animations: {
                guard let self = self else { return }
                self.countdownLabel.alpha = 1
                self.speedUpLabel.alpha = 0
            }, completion: { _ in
                self?.isShowingSpeedUpLabel = false
            })
        }
    }
}

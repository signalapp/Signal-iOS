import Accelerate

@objc(LKVoiceMessageViewDelegate)
protocol VoiceMessageViewDelegate {

    func showLoader()
    func hideLoader()
}

@objc(LKVoiceMessageView)
final class VoiceMessageView : UIView {
    private let voiceMessage: TSAttachment
    private let isOutgoing: Bool
    private var volumeSamples: [Float] = [] { didSet { updateShapeLayers() } }
    private var progress: CGFloat = 0
    @objc var delegate: VoiceMessageViewDelegate?
    @objc var duration: Int = 0 { didSet { updateDurationLabel() } }

    // MARK: Components
    private lazy var durationLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        return result
    }()

    private lazy var backgroundShapeLayer: CAShapeLayer = {
        let result = CAShapeLayer()
        result.fillColor = Colors.text.cgColor
        return result
    }()

    private lazy var foregroundShapeLayer: CAShapeLayer = {
        let result = CAShapeLayer()
        result.fillColor = (isLightMode && isOutgoing) ? UIColor.white.cgColor : Colors.accent.cgColor
        return result
    }()

    // MARK: Settings
    private let vMargin: CGFloat = 0
    private let sampleSpacing: CGFloat = 1

    @objc public static let contentHeight: CGFloat = 32

    // MARK: Initialization
    @objc(initWithVoiceMessage:isOutgoing:)
    init(voiceMessage: TSAttachment, isOutgoing: Bool) {
        self.voiceMessage = voiceMessage
        self.isOutgoing = isOutgoing
        super.init(frame: CGRect.zero)
    }

    override init(frame: CGRect) {
        preconditionFailure("Use init(voiceMessage:associatedWith:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(voiceMessage:associatedWith:) instead.")
    }

    @objc func initialize() {
        setUpViewHierarchy()
        if voiceMessage.isDownloaded {
            guard let url = (voiceMessage as? TSAttachmentStream)?.originalMediaURL else {
                return print("[Loki] Couldn't get URL for voice message.")
            }
            let targetSampleCount = 48
            if let cachedVolumeSamples = Storage.getVolumeSamples(for: voiceMessage.uniqueId!), cachedVolumeSamples.count == targetSampleCount {
                self.volumeSamples = cachedVolumeSamples
                self.delegate?.hideLoader()
            } else {
                let voiceMessageID = voiceMessage.uniqueId!
                AudioUtilities.getVolumeSamples(for: url, targetSampleCount: targetSampleCount).done(on: DispatchQueue.main) { [weak self] volumeSamples in
                    guard let self = self else { return }
                    self.volumeSamples = volumeSamples
                    Storage.write { transaction in
                        Storage.setVolumeSamples(for: voiceMessageID, to: volumeSamples, using: transaction)
                    }
                    self.durationLabel.alpha = 1
                    self.delegate?.hideLoader()
                }.catch(on: DispatchQueue.main) { error in
                    print("[Loki] Couldn't sample audio file due to error: \(error).")
                }
            }
        } else {
            durationLabel.alpha = 0
            delegate?.showLoader()
        }
    }

    private func setUpViewHierarchy() {
        set(.width, to: 200)
        set(.height, to: VoiceMessageView.contentHeight)
        layer.insertSublayer(backgroundShapeLayer, at: 0)
        layer.insertSublayer(foregroundShapeLayer, at: 1)
        addSubview(durationLabel)
        durationLabel.center(.vertical, in: self)
        durationLabel.pin(.trailing, to: .trailing, of: self)
    }

    // MARK: UI & Updating
    override func layoutSubviews() {
        super.layoutSubviews()
        updateShapeLayers()
    }

    @objc(updateForProgress:)
    func update(for progress: CGFloat) {
        self.progress = progress
        updateShapeLayers()
    }

    private func updateShapeLayers() {
        guard !volumeSamples.isEmpty else { return }
        let sMin = CGFloat(volumeSamples.min()!)
        let sMax = CGFloat(volumeSamples.max()!)
        let w = width() - durationLabel.width() - Values.smallSpacing
        let h = height() - 2 * vMargin
        let sW = (w - sampleSpacing * CGFloat(volumeSamples.count - 1)) / CGFloat(volumeSamples.count)
        let backgroundPath = UIBezierPath()
        let foregroundPath = UIBezierPath()
        for (i, value) in volumeSamples.enumerated() {
            let x = CGFloat(i) * (sW + sampleSpacing)
            let fraction = (CGFloat(value) - sMin) / (sMax - sMin)
            let sH = max(8, h * fraction)
            let y = vMargin + (h - sH) / 2
            let subPath = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: sW, height: sH), cornerRadius: sW / 2)
            backgroundPath.append(subPath)
            if progress > CGFloat(i) / CGFloat(volumeSamples.count) { foregroundPath.append(subPath) }
        }
        backgroundPath.close()
        foregroundPath.close()
        backgroundShapeLayer.path = backgroundPath.cgPath
        foregroundShapeLayer.path = foregroundPath.cgPath
    }

    private func updateDurationLabel() {
        durationLabel.text = OWSFormat.formatDurationSeconds(duration)
        updateShapeLayers()
    }
}

import Accelerate

@objc(LKVoiceMessageView2)
final class VoiceMessageView2 : UIView {
    private let voiceMessage: TSAttachment
    private var isAnimating = false
    private var volumeSamples: [Float] = [] { didSet { updateShapeLayers() } }
    private var progress: CGFloat = 0

    // MARK: Components
    private lazy var loader: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.text.withAlphaComponent(0.2)
        return result
    }()

    private lazy var backgroundShapeLayer: CAShapeLayer = {
        let result = CAShapeLayer()
        result.fillColor = Colors.text.cgColor
        return result
    }()

    private lazy var foregroundShapeLayer: CAShapeLayer = {
        let result = CAShapeLayer()
        result.fillColor = Colors.accent.cgColor
        return result
    }()

    // MARK: Settings
    private let margin: CGFloat = 4
    private let sampleSpacing: CGFloat = 1

    @objc public static let contentHeight: CGFloat = 40

    // MARK: Initialization
    @objc(initWithVoiceMessage:)
    init(voiceMessage: TSAttachment) {
        self.voiceMessage = voiceMessage
        super.init(frame: CGRect.zero)
        initialize()
    }

    override init(frame: CGRect) {
        preconditionFailure("Use init(voiceMessage:associatedWith:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(voiceMessage:associatedWith:) instead.")
    }

    private func initialize() {
        setUpViewHierarchy()
        if voiceMessage.isDownloaded {
            loader.alpha = 0
            guard let url = (voiceMessage as? TSAttachmentStream)?.originalMediaURL else {
                return print("[Loki] Couldn't get URL for voice message.")
            }
            if let cachedVolumeSamples = Storage.getVolumeSamples(for: voiceMessage.uniqueId!) {
                self.volumeSamples = cachedVolumeSamples
                self.stopAnimating()
            } else {
                let voiceMessageID = voiceMessage.uniqueId!
                AudioUtilities.getVolumeSamples(for: url).done(on: DispatchQueue.main) { [weak self] volumeSamples in
                    guard let self = self else { return }
                    self.volumeSamples = volumeSamples
                    Storage.write { transaction in
                        Storage.setVolumeSamples(for: voiceMessageID, to: volumeSamples, using: transaction)
                    }
                    self.stopAnimating()
                }.catch(on: DispatchQueue.main) { error in
                    print("[Loki] Couldn't sample audio file due to error: \(error).")
                }
            }
        } else {
            showLoader()
        }
    }

    private func setUpViewHierarchy() {
        set(.width, to: 200)
        set(.height, to: VoiceMessageView2.contentHeight)
        addSubview(loader)
        loader.pin(to: self)
        layer.insertSublayer(backgroundShapeLayer, at: 0)
        layer.insertSublayer(foregroundShapeLayer, at: 1)
    }

    // MARK: UI & Updating
    private func showLoader() {
        isAnimating = true
        loader.alpha = 1
        animateLoader()
    }

    private func animateLoader() {
        loader.frame = CGRect(x: 0, y: 0, width: 0, height: VoiceMessageView2.contentHeight)
        UIView.animate(withDuration: 2) { [weak self] in
            self?.loader.frame = CGRect(x: 0, y: 0, width: 200, height: VoiceMessageView2.contentHeight)
        } completion: { [weak self] _ in
            guard let self = self else { return }
            if self.isAnimating { self.animateLoader() }
        }
    }

    private func stopAnimating() {
        isAnimating = false
        loader.alpha = 0
    }

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
        let max = CGFloat(volumeSamples.max()!)
        let min = CGFloat(volumeSamples.min()!)
        let w = width() - 2 * margin
        let h = height() - 2 * margin
        let sW = (w - sampleSpacing * CGFloat(volumeSamples.count)) / CGFloat(volumeSamples.count)
        let backgroundPath = UIBezierPath()
        let foregroundPath = UIBezierPath()
        for (i, value) in volumeSamples.enumerated() {
            let x = margin + CGFloat(i) * (sW + sampleSpacing)
            let fraction = (CGFloat(value) - min) / (max - min)
            let sH = h * fraction
            let y = margin + (h - sH) / 2
            let subPath = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: sW, height: sH), cornerRadius: sW / 2)
            backgroundPath.append(subPath)
            if progress > CGFloat(i) / CGFloat(volumeSamples.count) { foregroundPath.append(subPath) }
        }
        backgroundPath.close()
        foregroundPath.close()
        backgroundShapeLayer.path = backgroundPath.cgPath
        foregroundShapeLayer.path = foregroundPath.cgPath
    }
}

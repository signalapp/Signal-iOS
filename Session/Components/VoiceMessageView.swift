import Accelerate
import NVActivityIndicatorView

@objc(LKVoiceMessageView)
final class VoiceMessageView : UIView {
    private let voiceMessage: TSAttachment
    private let isOutgoing: Bool
    private var isLoading = false
    private var isForcedAnimation = false
    private var volumeSamples: [Float] = [] { didSet { updateShapeLayers() } }
    @objc var progress: CGFloat = 0 { didSet { updateShapeLayers() } }
    @objc var duration: Int = 0 { didSet { updateDurationLabel() } }
    @objc var isPlaying = false { didSet { updateToggleImageView() } }

    // MARK: Components
    private lazy var toggleImageView = UIImageView(image: #imageLiteral(resourceName: "Play"))

    private lazy var spinner = NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: .black, padding: nil)

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
    private let leadingInset: CGFloat = 0
    private let sampleSpacing: CGFloat = 1
    private let targetSampleCount = 48
    private let toggleContainerSize: CGFloat = 32
    private let vMargin: CGFloat = 0

    @objc public static let contentHeight: CGFloat = 40

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
            if let cachedVolumeSamples = Storage.shared.getVolumeSamples(for: voiceMessage.uniqueId!), cachedVolumeSamples.count == targetSampleCount {
                self.hideLoader()
                self.volumeSamples = cachedVolumeSamples
            } else {
                let voiceMessageID = voiceMessage.uniqueId!
                AudioUtilities.getVolumeSamples(for: url, targetSampleCount: targetSampleCount).done(on: DispatchQueue.main) { [weak self] volumeSamples in
                    guard let self = self else { return }
                    self.hideLoader()
                    self.isForcedAnimation = true
                    self.volumeSamples = volumeSamples
                    Storage.write { transaction in
                        Storage.shared.setVolumeSamples(for: voiceMessageID, to: volumeSamples, using: transaction)
                    }
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
        set(.height, to: VoiceMessageView.contentHeight)
        layer.insertSublayer(backgroundShapeLayer, at: 0)
        layer.insertSublayer(foregroundShapeLayer, at: 1)
        let toggleContainer = UIView()
        toggleContainer.clipsToBounds = false
        toggleContainer.addSubview(toggleImageView)
        toggleImageView.set(.width, to: 12)
        toggleImageView.set(.height, to: 12)
        toggleImageView.center(in: toggleContainer)
        toggleContainer.addSubview(spinner)
        spinner.set(.width, to: 24)
        spinner.set(.height, to: 24)
        spinner.center(in: toggleContainer)
        toggleContainer.set(.width, to: toggleContainerSize)
        toggleContainer.set(.height, to: toggleContainerSize)
        toggleContainer.layer.cornerRadius = toggleContainerSize / 2
        toggleContainer.backgroundColor = UIColor.white
        let glowRadius: CGFloat = isLightMode ? 1 : 2
        let glowColor = isLightMode ? UIColor.black.withAlphaComponent(0.4) : UIColor.black
        let glowConfiguration = UIView.CircularGlowConfiguration(size: toggleContainerSize, color: glowColor, radius: glowRadius)
        toggleContainer.setCircularGlow(with: glowConfiguration)
        addSubview(toggleContainer)
        toggleContainer.center(.vertical, in: self)
        toggleContainer.pin(.leading, to: .leading, of: self, withInset: leadingInset)
        addSubview(durationLabel)
        durationLabel.center(.vertical, in: self)
        durationLabel.pin(.trailing, to: .trailing, of: self)
    }

    // MARK: UI & Updating
    private func showLoader() {
        isLoading = true
        toggleImageView.isHidden = true
        spinner.startAnimating()
        spinner.isHidden = false
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self = self else { return timer.invalidate() }
            if self.isLoading {
                self.updateFakeVolumeSamples()
            } else {
                timer.invalidate()
            }
        }
        updateFakeVolumeSamples()
    }

    private func updateFakeVolumeSamples() {
        let fakeVolumeSamples = (0..<targetSampleCount).map { _ in Float.random(in: 0...1) }
        volumeSamples = fakeVolumeSamples
    }

    private func hideLoader() {
        isLoading = false
        toggleImageView.isHidden = false
        spinner.stopAnimating()
        spinner.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateShapeLayers()
    }

    private func updateShapeLayers() {
        clipsToBounds = false // Bit of a hack to do this here, but the containing stack view turns this off all the time
        guard !volumeSamples.isEmpty else { return }
        let sMin = CGFloat(volumeSamples.min()!)
        let sMax = CGFloat(volumeSamples.max()!)
        let w = width() - leadingInset - toggleContainerSize - durationLabel.width() - 2 * Values.smallSpacing
        let h = height() - 2 * vMargin
        let sW = (w - sampleSpacing * CGFloat(volumeSamples.count - 1)) / CGFloat(volumeSamples.count)
        let backgroundPath = UIBezierPath()
        let foregroundPath = UIBezierPath()
        for (i, value) in volumeSamples.enumerated() {
            let x = leadingInset + toggleContainerSize + Values.smallSpacing + CGFloat(i) * (sW + sampleSpacing)
            let fraction = (CGFloat(value) - sMin) / (sMax - sMin)
            let sH = max(8, h * fraction)
            let y = vMargin + (h - sH) / 2
            let subPath = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: sW, height: sH), cornerRadius: sW / 2)
            backgroundPath.append(subPath)
            if progress > CGFloat(i) / CGFloat(volumeSamples.count) { foregroundPath.append(subPath) }
        }
        backgroundPath.close()
        foregroundPath.close()
        if isLoading || isForcedAnimation {
            let animation = CABasicAnimation(keyPath: "path")
            animation.duration = 0.25
            animation.toValue = backgroundPath
            animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
            backgroundShapeLayer.add(animation, forKey: "path")
            backgroundShapeLayer.path = backgroundPath.cgPath
        } else {
            backgroundShapeLayer.path = backgroundPath.cgPath
        }
        foregroundShapeLayer.path = foregroundPath.cgPath
        isForcedAnimation = false
    }

    private func updateDurationLabel() {
        durationLabel.text = OWSFormat.formatDurationSeconds(duration)
        updateShapeLayers()
    }

    private func updateToggleImageView() {
        toggleImageView.image = isPlaying ? #imageLiteral(resourceName: "Pause") : #imageLiteral(resourceName: "Play")
    }

    // MARK: Interaction
    @objc(getCurrentTime:)
    func getCurrentTime(for panGestureRecognizer: UIPanGestureRecognizer) -> TimeInterval {
        guard voiceMessage.isDownloaded else { return 0 }
        let locationInSelf = panGestureRecognizer.location(in: self)
        let waveformFrameOrigin = CGPoint(x: leadingInset + toggleContainerSize + Values.smallSpacing, y: vMargin)
        let waveformFrameSize = CGSize(width: width() - leadingInset - toggleContainerSize - durationLabel.width() - 2 * Values.smallSpacing,
            height: height() - 2 * vMargin)
        let waveformFrame = CGRect(origin: waveformFrameOrigin, size: waveformFrameSize)
        guard waveformFrame.contains(locationInSelf) else { return 0 }
        let fraction = (locationInSelf.x - waveformFrame.minX) / (waveformFrame.maxX - waveformFrame.minX)
        return Double(fraction) * Double(duration)
    }
}

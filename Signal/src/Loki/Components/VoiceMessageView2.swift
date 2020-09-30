import Accelerate

@objc(LKVoiceMessageView2)
final class VoiceMessageView2 : UIView {
    private let audioFileURL: URL
    private let player: AVAudioPlayer
    private var duration: Double = 1
    private var isAnimating = false
    private var volumeSamples: [Float] = [] { didSet { updateShapeLayer() } }

    // MARK: Components
    private lazy var loader: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.text.withAlphaComponent(0.2)
        result.layer.cornerRadius = Values.messageBubbleCornerRadius
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
    private let margin = Values.smallSpacing
    private let sampleSpacing: CGFloat = 1

    // MARK: Initialization
    init(audioFileURL: URL) {
        self.audioFileURL = audioFileURL
        player = try! AVAudioPlayer(contentsOf: audioFileURL)
        super.init(frame: CGRect.zero)
        initialize()
    }

    override init(frame: CGRect) {
        preconditionFailure("Use init(audioFileURL:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(audioFileURL:) instead.")
    }

    private func initialize() {
        setUpViewHierarchy()
        AudioUtilities.getVolumeSamples(for: audioFileURL).done(on: DispatchQueue.main) { [weak self] duration, volumeSamples in
            guard let self = self else { return }
            self.duration = duration
            self.volumeSamples = volumeSamples
            self.stopAnimating()
        }.catch(on: DispatchQueue.main) { error in
            print("[Loki] Couldn't sample audio file due to error: \(error).")
        }
    }

    private func setUpViewHierarchy() {
        set(.width, to: 200)
        set(.height, to: 40)
        addSubview(loader)
        loader.pin(to: self)
        backgroundColor = Colors.sentMessageBackground
        layer.cornerRadius = Values.messageBubbleCornerRadius
        layer.insertSublayer(backgroundShapeLayer, at: 0)
        layer.insertSublayer(foregroundShapeLayer, at: 1)
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(togglePlayback))
        addGestureRecognizer(tapGestureRecognizer)
        showLoader()
    }

    // MARK: User Interface
    private func showLoader() {
        isAnimating = true
        loader.alpha = 1
        animateLoader()
    }

    private func animateLoader() {
        loader.frame = CGRect(x: 0, y: 0, width: 0, height: 40)
        UIView.animate(withDuration: 2) { [weak self] in
            self?.loader.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
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
        updateShapeLayer()
    }

    private func updateShapeLayer() {
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
            if player.currentTime / duration > Double(i) / Double(volumeSamples.count) { foregroundPath.append(subPath) }
        }
        backgroundPath.close()
        foregroundPath.close()
        backgroundShapeLayer.path = backgroundPath.cgPath
        foregroundShapeLayer.path = foregroundPath.cgPath
    }

    @objc private func togglePlayback() {
        player.play()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else { return timer.invalidate() }
            self.updateShapeLayer()
            if !self.player.isPlaying { timer.invalidate() }
        }
    }
}

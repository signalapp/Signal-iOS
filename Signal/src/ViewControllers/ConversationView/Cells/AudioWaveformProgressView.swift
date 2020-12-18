//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

@objc
class AudioWaveformProgressView: UIView {
    @objc
    var playedColor: UIColor = Theme.primaryTextColor {
        didSet {
            playedShapeLayer.fillColor = playedColor.cgColor
        }
    }

    @objc
    var unplayedColor: UIColor = Theme.secondaryTextAndIconColor {
        didSet {
            unplayedShapeLayer.fillColor = unplayedColor.cgColor

            let strokeColorKeypath = AnimationKeypath(keypath: "**.Stroke 1.Color")
            loadingAnimation.setValueProvider(ColorValueProvider(unplayedColor.lottieColorValue), keypath: strokeColorKeypath)
        }
    }

    @objc
    var thumbColor: UIColor = Theme.primaryTextColor {
        didSet {
            thumbImageView.tintColor = thumbColor
        }
    }

    @objc
    var value: CGFloat = 0 {
        didSet {
            guard value != oldValue else { return }
            redrawSamples()
        }
    }

    @objc
    var audioWaveform: AudioWaveform? {
        didSet {
            guard audioWaveform != oldValue else { return }
            audioWaveform?.addSamplingObserver(self)
        }
    }

    public override var bounds: CGRect {
        didSet {
            guard bounds != oldValue else { return }
            redrawSamples()
        }
    }

    public override var frame: CGRect {
        didSet {
            guard frame != oldValue else { return }
            redrawSamples()
        }
    }

    public override var center: CGPoint {
        didSet {
            guard center != oldValue else { return }
            redrawSamples()
        }
    }

    private let thumbImageView = UIImageView(
        image: UIImage(named: "audio_message_thumb")?.withRenderingMode(.alwaysTemplate)
    )
    private let playedShapeLayer = CAShapeLayer()
    private let unplayedShapeLayer = CAShapeLayer()
    private let loadingAnimation = AnimationView(name: "waveformLoading")

    @objc
    init() {
        super.init(frame: .zero)

        playedShapeLayer.fillColor = playedColor.cgColor
        layer.addSublayer(playedShapeLayer)

        unplayedShapeLayer.fillColor = unplayedColor.cgColor
        layer.addSublayer(unplayedShapeLayer)

        thumbImageView.tintColor = thumbColor
        addSubview(thumbImageView)

        loadingAnimation.contentMode = .scaleAspectFit
        loadingAnimation.loopMode = .loop
        loadingAnimation.backgroundBehavior = .pauseAndRestore

        addSubview(loadingAnimation)
        loadingAnimation.autoHCenterInSuperview()
        loadingAnimation.autoPinHeightToSuperview()
        loadingAnimation.isHidden = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func redrawSamples() {
        AssertIsOnMainThread()

        // Show the loading state if sampling of the waveform hasn't finished yet.
        // TODO: This will eventually be a lottie animation of a waveform moving up and down
        func resetContents(showLoadingAnimation: Bool) {
            playedShapeLayer.path = nil
            unplayedShapeLayer.path = nil
            thumbImageView.isHidden = true
            if showLoadingAnimation {
                loadingAnimation.isHidden = false
                loadingAnimation.play()
            }
        }

        guard audioWaveform?.isSamplingComplete == true else {
            resetContents(showLoadingAnimation: true)
            return
        }

        loadingAnimation.stop()
        loadingAnimation.isHidden = true
        thumbImageView.isHidden = false

        let sampleWidth: CGFloat = 2
        let minSampleSpacing: CGFloat = 2
        let minSampleHeight: CGFloat = 2

        let playedBezierPath = UIBezierPath()
        let unplayedBezierPath = UIBezierPath()

        // Calculate the number of lines we want to render based on the view width.
        let targetSamplesCount = Int((width + minSampleSpacing) / (sampleWidth + minSampleSpacing))

        guard let amplitudes = audioWaveform?.normalizedLevelsToDisplay(sampleCount: targetSamplesCount),
              amplitudes.count > 0 else {
            owsFailDebug("Missing sample amplitudes.")
            resetContents(showLoadingAnimation: false)
            return
        }
        // We might not have enough samples.
        let samplesCount = min(targetSamplesCount, amplitudes.count)

        let sampleSpacingCount = max(0, samplesCount - 1)
        let sampleSpacing: CGFloat
        if sampleSpacingCount > 0 {
            // Divide the remaining space evenly between the samples.
            let remainingSpace = max(0, width - (sampleWidth * CGFloat(samplesCount)))
            sampleSpacing = remainingSpace / CGFloat(sampleSpacingCount)
        } else {
            sampleSpacing = 0
        }

        playedShapeLayer.frame = layer.frame
        unplayedShapeLayer.frame = layer.frame

        let progress = self.value
        var thumbXPos = width * progress
        if CurrentAppContext().isRTL { thumbXPos = width - thumbXPos }
        thumbImageView.center = CGPoint(x: thumbXPos, y: layer.frame.center.y)

        defer {
            playedShapeLayer.path = playedBezierPath.cgPath
            unplayedShapeLayer.path = unplayedBezierPath.cgPath
        }

        let playedLines = Int(CGFloat(amplitudes.count) * progress)

        for (x, sample) in amplitudes.enumerated() {
            let path: UIBezierPath = ((x > playedLines) || (progress == 0)) ? unplayedBezierPath : playedBezierPath

            // The sample represents the magnitude of sound at this point
            // from 0 (silence) to 1 (loudest possible value). Calculate the
            // height of the sample view so that the loudest value is the
            // full height of this view.
            let height = max(minSampleHeight, frame.size.height * CGFloat(sample))

            // Center the sample vertically.
            let yPos = frame.center.y - height / 2

            var xPos = CGFloat(x) * (sampleWidth + sampleSpacing)
            if CurrentAppContext().isRTL { xPos = width - xPos }

            let sampleFrame = CGRect(
                x: xPos,
                y: yPos,
                width: sampleWidth,
                height: height
            )

            path.append(UIBezierPath(roundedRect: sampleFrame, cornerRadius: sampleWidth / 2))
        }
    }
}

extension AudioWaveformProgressView: AudioWaveformSamplingObserver {
    func audioWaveformDidFinishSampling(_ audioWaveform: AudioWaveform) {
        DispatchQueue.main.async { self.redrawSamples() }
    }
}

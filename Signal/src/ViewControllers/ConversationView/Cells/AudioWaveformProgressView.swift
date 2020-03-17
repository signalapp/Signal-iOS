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
    var sampleWidth: CGFloat = 2

    @objc
    var sampleSpacing: CGFloat = 2

    @objc
    var minSampleHeight: CGFloat = 2

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
        guard audioWaveform?.isSamplingComplete == true else {
            thumbImageView.isHidden = true
            loadingAnimation.isHidden = false
            loadingAnimation.play()
            return
        }

        loadingAnimation.stop()
        loadingAnimation.isHidden = true
        thumbImageView.isHidden = false

        let playedBezierPath = UIBezierPath()
        let unplayedBezierPath = UIBezierPath()

        // Calculate the number of lines we want to render based on the view width.
        let numberOfSamplesToDraw = Int(width / (sampleWidth + sampleSpacing))
        let samplesWidth = CGFloat(numberOfSamplesToDraw) * (sampleWidth + sampleSpacing) - sampleSpacing
        let sampleHMargin = (width - samplesWidth) / 2

        playedShapeLayer.frame = layer.frame
        unplayedShapeLayer.frame = layer.frame

        var thumbXPos = sampleHMargin + (samplesWidth * value)
        if CurrentAppContext().isRTL { thumbXPos = samplesWidth - thumbXPos }
        thumbImageView.center = CGPoint(x: thumbXPos, y: layer.frame.center.y)

        defer {
            playedShapeLayer.path = playedBezierPath.cgPath
            unplayedShapeLayer.path = unplayedBezierPath.cgPath
        }

        guard let amplitudes = audioWaveform?.normalizedLevelsToDisplay(sampleCount: numberOfSamplesToDraw),
            amplitudes.count > 0 else { return }

        let playedLines = Int(CGFloat(amplitudes.count) * value)

        for (x, sample) in amplitudes.enumerated() {
            let path: UIBezierPath = ((x > playedLines) || (value == 0)) ? unplayedBezierPath : playedBezierPath

            // The sample represents the magnitude of sound at this point
            // from 0 (silence) to 1 (loudest possible value). Calculate the
            // height of the sample view so that the loudest value is the
            // full height of this view.
            let height = max(minSampleHeight, frame.size.height * CGFloat(sample))

            // Center the sample vertically.
            let yPos = frame.center.y - height / 2

            var xPos = CGFloat(x) * (sampleWidth + sampleSpacing) + sampleHMargin
            if CurrentAppContext().isRTL { xPos = samplesWidth - xPos }

            path.append(
                UIBezierPath(
                    roundedRect: CGRect(
                        x: xPos,
                        y: yPos,
                        width: sampleWidth,
                        height: height
                    ),
                    cornerRadius: sampleWidth / 2
                )
            )
        }
    }
}

extension AudioWaveformProgressView: AudioWaveformSamplingObserver {
    func audioWaveformDidFinishSampling(_ audioWaveform: AudioWaveform) {
        DispatchQueue.main.async { self.redrawSamples() }
    }
}

//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import Accelerate

@objc
class AudioWaveformProgressView: UIView {
    @objc
    var playedColor: UIColor = Theme.primaryColor {
        didSet {
            playedShapeLayer.fillColor = playedColor.cgColor
        }
    }

    @objc
    var unplayedColor: UIColor = Theme.secondaryColor {
        didSet {
            activityIndicator.color = unplayedColor
            unplayedShapeLayer.fillColor = unplayedColor.cgColor
        }
    }

    @objc
    var thumbColor: UIColor = Theme.primaryColor {
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
    private let activityIndicator = UIActivityIndicatorView(style: .white)

    @objc
    init() {
        super.init(frame: .zero)

        playedShapeLayer.fillColor = playedColor.cgColor
        layer.addSublayer(playedShapeLayer)

        unplayedShapeLayer.fillColor = unplayedColor.cgColor
        layer.addSublayer(unplayedShapeLayer)

        thumbImageView.tintColor = thumbColor
        addSubview(thumbImageView)

        addSubview(activityIndicator)
        activityIndicator.autoCenterInSuperview()
        activityIndicator.isHidden = true
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
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()
            return
        }

        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        thumbImageView.isHidden = false

        let playedBezierPath = UIBezierPath()
        let unplayedBezierPath = UIBezierPath()

        // Calculate the number of lines we want to render based on the view width.
        let numberOfSamplesToDraw = Int(width() / (sampleWidth + sampleSpacing))
        let samplesWidth = CGFloat(numberOfSamplesToDraw) * (sampleWidth + sampleSpacing) - sampleSpacing
        let sampleHMargin = (width() - samplesWidth) / 2

        playedShapeLayer.frame = layer.frame
        unplayedShapeLayer.frame = layer.frame
        thumbImageView.center = CGPoint(x: sampleHMargin + (samplesWidth * value), y: layer.frame.center.y)

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

            path.append(
                UIBezierPath(
                    roundedRect: CGRect(
                        x: CGFloat(x) * (sampleWidth + sampleSpacing) + sampleHMargin,
                        y: yPos,
                        width: sampleWidth,
                        height: height
                    ),
                    cornerRadius: sampleWidth
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

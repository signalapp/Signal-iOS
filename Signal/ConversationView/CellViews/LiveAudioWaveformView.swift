//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI

class LiveAudioWaveformView: UIView {
    var playedColor: UIColor = .Signal.label {
        didSet {
            shapeLayer.fillColor = playedColor.cgColor
        }
    }

    private let shapeLayer = CAShapeLayer()
    private let fadeMaskLayer = CAGradientLayer()
    private var samples: [Float] = []
    
    // Config
    private let sampleWidth: CGFloat = 2
    private let minSampleSpacing: CGFloat = 2
    private let minSampleHeight: CGFloat = 2
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.addSublayer(shapeLayer)
        
        // Add a subtle fade on the left edge so samples don't clip harshly
        fadeMaskLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.cgColor
        ]
        fadeMaskLayer.locations = [0.0, 0.15]
        fadeMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.mask = fadeMaskLayer
        
        clipsToBounds = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer.fillColor = playedColor.cgColor
        shapeLayer.frame = bounds
        fadeMaskLayer.frame = bounds
        redrawSamples()
    }
    
    func appendSample(powerLevel: Float) {
        // powerLevel is usually -160 to 0.
        // We need to map it to a scale of 0 to 1.
        let minDb: Float = -35.0
        let clampedLevel = max(minDb, powerLevel)
        let normalized = max(0.0, (clampedLevel - minDb) / abs(minDb))
        
        // Optionally apply a curve (e.g. sqrt) for better visual pop
        let displaySample = sqrt(normalized)
        
        samples.append(displaySample)
        redrawSamples()
        
        // Smoothly slide the new sample into view using Core Animation
        let sampleTotalWidth = sampleWidth + minSampleSpacing
        
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = sampleTotalWidth
        animation.toValue = 0
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        
        shapeLayer.add(animation, forKey: "slideLeft")
        shapeLayer.transform = CATransform3DIdentity
    }
    
    private func redrawSamples() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        
        let path = UIBezierPath()
        
        // Calculate max samples that fit in the view
        let sampleTotalWidth = sampleWidth + minSampleSpacing
        let maxSamples = Int(bounds.width / sampleTotalWidth)
        
        // Determine the slice of samples to display (always show the most recent ones)
        let startIndex = max(0, samples.count - maxSamples)
        let visibleSamples = samples[startIndex...]
        
        let totalSamplesWidth = CGFloat(visibleSamples.count) * sampleTotalWidth
        let startX = bounds.width - totalSamplesWidth
        
        for (i, sample) in visibleSamples.enumerated() {
            let safeSample = sample.isNaN ? 0 : sample
            let sampleHeight = max(minSampleHeight, bounds.height * CGFloat(safeSample))
            let yPos = bounds.midY - sampleHeight / 2
            
            let xPos = startX + CGFloat(i) * sampleTotalWidth
            
            let rect = CGRect(x: xPos, y: yPos, width: sampleWidth, height: sampleHeight)
            path.append(UIBezierPath(roundedRect: rect, cornerRadius: sampleWidth / 2))
        }
        
        shapeLayer.path = path.cgPath
    }
    
    func reset() {
        samples.removeAll()
        redrawSamples()
    }
}

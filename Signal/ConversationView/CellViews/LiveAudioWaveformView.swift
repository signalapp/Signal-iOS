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
    private var samples: [Float] = []
    
    // Config
    private let sampleWidth: CGFloat = 2
    private let minSampleSpacing: CGFloat = 2
    private let minSampleHeight: CGFloat = 2
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        shapeLayer.fillColor = playedColor.cgColor
        layer.addSublayer(shapeLayer)
        
        clipsToBounds = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer.frame = bounds
        redrawSamples()
    }
    
    func appendSample(powerLevel: Float) {
        // powerLevel is usually -160 to 0.
        // We need to map it to a scale of 0 to 1.
        let minDb: Float = -60.0
        let clampedLevel = max(minDb, powerLevel)
        let normalized = (clampedLevel - minDb) / abs(minDb)
        
        // Optionally apply a curve (e.g. sqrt) for better visual pop
        let displaySample = sqrt(normalized)
        
        samples.append(displaySample)
        redrawSamples()
    }
    
    private func redrawSamples() {
        guard width > 0, height > 0 else { return }
        
        let path = UIBezierPath()
        
        // Calculate max samples that fit in the view
        let sampleTotalWidth = sampleWidth + minSampleSpacing
        let maxSamples = Int(width / sampleTotalWidth)
        
        // Determine the slice of samples to display (always show the most recent ones)
        let startIndex = max(0, samples.count - maxSamples)
        let visibleSamples = samples[startIndex...]
        
        for (i, sample) in visibleSamples.enumerated() {
            let sampleHeight = max(minSampleHeight, height * CGFloat(sample))
            let yPos = bounds.midY - sampleHeight / 2
            
            let xPos = CGFloat(i) * sampleTotalWidth
            
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

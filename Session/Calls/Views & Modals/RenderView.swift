// Copyright © 2021 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import AVFoundation
import CoreMedia

class RenderView: UIView {
    
    private lazy var displayLayer: AVSampleBufferDisplayLayer = {
        let result = AVSampleBufferDisplayLayer()
        result.videoGravity = .resizeAspectFill
        return result
    }()
    
    init() {
        super.init(frame: CGRect.zero)
        self.layer.addSublayer(displayLayer)
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(message:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(coder:) instead.")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer.frame = self.bounds
    }
    
    public func enqueue(sampleBuffer: CMSampleBuffer) {
        displayLayer.enqueue(sampleBuffer)
    }

}

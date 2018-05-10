//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

@objc
class SignalNavigationBar: UINavigationBar {
//    var isCallActive: Bool = false {
//        didSet {
//            guard oldValue != isCallActive else {
//                return
//            }
//            
//            if isCallActive {
//                self.addSubview(callBanner)
////                callBanner.autoPinEdge(toSuperviewEdge: .top)
//                callBanner.autoPinEdge(toSuperviewEdge: .leading)
//                callBanner.autoPinEdge(toSuperviewEdge: .trailing)
//            } else {
//                callBanner.removeFromSuperview()
//            }
//        }
//    }
//    
//    let callBanner: UIView
//    let callLabel: UILabel
//    let callBannerHeight: CGFloat = 40
//
//    override init(frame: CGRect) {
//        callBanner = UIView()
//        callBanner.backgroundColor = .green
//        callBanner.autoSetDimension(.height, toSize: callBannerHeight)
//        
//        callLabel = UILabel()
//        callLabel.text = "Return to your call..."
//        callLabel.textColor = .white
//        
//        callBanner.addSubview(callLabel)
//        callLabel.autoPinBottomToSuperviewMargin()
//        callLabel.autoHCenterInSuperview()
//        callLabel.setCompressionResistanceHigh()
//        callLabel.setContentHuggingHigh()
//        
//        super.init(frame: frame)
//        
//        let debugTap = UITapGestureRecognizer(target: self, action: #selector(didTap))
//        self.addGestureRecognizer(debugTap)
//    }
//    
//    @objc
//    func didTap(sender: UITapGestureRecognizer) {
//        Logger.debug("\(self.logTag) in \(#function)")
//        self.isCallActive = !self.isCallActive
//    }
//
//    
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        if OWSWindowManager.shared().hasCall() {
            return CGSize(width: UIScreen.main.bounds.width, height: 30)
        } else {
            return super.sizeThatFits(size)
        }
    }
}

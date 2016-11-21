//  Created by Michael Kirk on 10/12/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import UIKit

@objc(OWSHighlightableLabelDelegate)
protocol HighlightableLabelDelegate {
    func didHighlightLabel(_ label:HighlightableLabel, completion: (()->())?) -> ()
}

@objc(OWSHighlightableLabel)
class HighlightableLabel : UILabel {

    deinit {
        NotificationCenter.default.removeObserver(self);
    }

    var delegate: HighlightableLabelDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestureRecognizer()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupGestureRecognizer()
    }

    @IBInspectable var borderColor: UIColor? {
        didSet {
            layer.borderColor = borderColor?.cgColor
        }
    }

    override func drawText(in rect: CGRect) {
        let insets = UIEdgeInsets.init(top: 5, left: 5, bottom: 5, right: 5)
        super.drawText(in: UIEdgeInsetsInsetRect(rect, insets))
    }

    func hideBorder() {
        layer.borderWidth = 0
    }

    func showBorder() {
        layer.borderWidth = 1.0
    }

    func setupGestureRecognizer() {
        isUserInteractionEnabled = true
        let longpressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(highlightGesture))
        addGestureRecognizer(longpressGestureRecognizer)
        NotificationCenter.default.addObserver(self, selector: #selector(hideBorder), name:NSNotification.Name.UIMenuControllerWillHideMenu, object: nil)
    }

    func highlightGesture(gestureRecognizer: UILongPressGestureRecognizer) {
        guard gestureRecognizer.state == .began else {
            return
        }

        becomeFirstResponder();
        showBorder()
        self.delegate?.didHighlightLabel(self, completion:{ self.hideBorder() })
    }
}

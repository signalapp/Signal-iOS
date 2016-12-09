//  Created by Michael Kirk on 11/28/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation
import UIKit

@objc(OWSActionableNavbarTitleView)
class ActionableNavbarTitleView: UIView {

    static let nibName = "ActionableNavbarTitleView"
    static let nib = UINib(nibName: nibName, bundle: nil)

    @IBOutlet var imageView: UIImageView!
    @IBOutlet var label: UILabel!

    var title: String? {
        get { return label.text }
        set { label.text = newValue }
    }

    // MARK: - Initializers

    class func loadFromNib() -> ActionableNavbarTitleView {
        let view = nib.instantiate(withOwner:self, options: nil).first as! ActionableNavbarTitleView
        return view
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    override required init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    func commonInit() {
        isUserInteractionEnabled = true
    }
}

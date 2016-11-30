//  Created by Michael Kirk on 11/30/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation
import UIKit

@objc(OWSNoSignalContactsView)
@IBDesignable class NoSignalContactsView: UIView {
    static let nibName = "NoSignalContactsView"

    @IBOutlet var headingLabel: UILabel!
    @IBOutlet var subheadingLabel: UILabel!
    @IBOutlet var inviteButton: UIButton!

    var view: UIView!

    // Mark: - Initialize

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    func commonInit() {
        xibSetup()
        localizeStrings()
    }

    func xibSetup() {
        view = loadViewFromNib()

        // use bounds not frame or it'll be offset
        view.frame = bounds

        // Make the view stretch with containing view
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Adding custom subview on top of our view (over any custom drawing > see note below)
        addSubview(view)
    }

    func localizeStrings() {
        headingLabel.text = NSLocalizedString("EMPTY_CONTACTS_LABEL_LINE1", comment:"Full width label displayed when attempting to compose message")
        subheadingLabel.text = NSLocalizedString("EMPTY_CONTACTS_LABEL_LINE2", comment:"Full width label displayed when attempting to compose message")
        let inviteText = NSLocalizedString("INVITE_FRIENDS_CONTACT_TABLE_BUTTON", comment:"Text for button at the top of the contact picker")
        inviteButton.setTitle(inviteText, for: .normal)
    }

    func loadViewFromNib() -> UIView {
        let bundle = Bundle(for: type(of:self))
        let nib = UINib(nibName: NoSignalContactsView.nibName, bundle: bundle)
        let view = nib.instantiate(withOwner:self, options: nil)[0] as! UIView
        
        return view
    }
}

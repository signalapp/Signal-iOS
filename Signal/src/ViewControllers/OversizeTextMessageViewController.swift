//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import WebRTC
import PromiseKit

class OversizeTextMessageViewController: OWSViewController {

    let TAG = "[OversizeTextMessageViewController]"

    let displayableText: String
    let attachmentStream: TSAttachmentStream

    // MARK: Initializers

    @available(*, unavailable, message:"use message: constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        displayableText = ""
        attachmentStream = TSAttachmentStream(contentType:"", sourceFilename:"")
        super.init(coder: aDecoder)
    }

    required init(displayableText: String, attachmentStream: TSAttachmentStream) {
        self.displayableText = displayableText
        self.attachmentStream = attachmentStream
        super.init(nibName: nil, bundle: nil)
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = NSLocalizedString("OVERSIZE_TEXT_MESSAGE_VIEW_TITLE",
                                                      comment: "The title of the 'oversize text message' view.")

        self.view.backgroundColor = UIColor.white

        let textView = UITextView()
        textView.textColor = UIColor.black
        textView.text = displayableText
        textView.font = UIFont.ows_dynamicTypeBody()
        textView.isEditable = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        self.view.addSubview(textView)
        textView.autoPinWidthToSuperview()
        textView.autoPin(toTopLayoutGuideOf : self, withInset: 0)

        let footerBar = UIToolbar()
        footerBar.barTintColor = UIColor.ows_signalBrandBlue()
        footerBar.setItems([
            UIBarButtonItem(barButtonSystemItem:.flexibleSpace,
                            target:nil,
                            action:nil),
            UIBarButtonItem(barButtonSystemItem:.action,
                            target:self,
                            action:#selector(shareWasPressed)),
            UIBarButtonItem(barButtonSystemItem:.flexibleSpace,
                            target:nil,
                            action:nil)
            ], animated: false)
        self.view.addSubview(footerBar)
        footerBar.autoPinWidthToSuperview()
        footerBar.autoPin(toBottomLayoutGuideOf : self, withInset: 0)
        footerBar.autoPinEdge(.top, to:.bottom, of:textView)
    }

    func shareWasPressed(sender: UIButton) {
        Logger.info("\(TAG) sharing oversize text.")

        AttachmentSharing.showShareUI(for:attachmentStream.mediaURL())
    }
}

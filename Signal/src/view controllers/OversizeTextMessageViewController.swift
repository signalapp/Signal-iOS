//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import WebRTC
import PromiseKit

class OversizeTextMessageViewController: UIViewController {

    let TAG = "[OversizeTextMessageViewController]"

    let message: TSMessage

    // MARK: Initializers

    @available(*, unavailable, message:"use message: constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        message = TSMessage()
        super.init(coder: aDecoder)
    }

    required init(message: TSMessage) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    // MARK: Attachment

    private func attachmentStream() -> TSAttachmentStream? {
        guard message.hasAttachments() else {
            Logger.error("\(TAG) message has no attachments.")
            assert(false)
            return nil
        }
        let attachmentIDRaw = message.attachmentIds[0]
        guard attachmentIDRaw is String else {
            Logger.error("\(TAG) message attachment id is not a string.")
            assert(false)
            return nil
        }
        let attachmentID = attachmentIDRaw as! String
        guard let attachment = TSAttachment.fetch(withUniqueID:attachmentID) else {
            Logger.error("\(TAG) could not load attachment.")
            assert(false)
            return nil
        }
        guard attachment.contentType == OWSMimeTypeOversizeTextMessage else {
            Logger.error("\(TAG) attachment has unexpected content type.")
            assert(false)
            return nil
        }
        guard attachment is TSAttachmentStream else {
            Logger.error("\(TAG) attachment has unexpected type.")
            assert(false)
            return nil
        }
        let stream = attachment as! TSAttachmentStream
        return stream
    }

    private func attachmentData() -> Data? {
        guard let stream = attachmentStream() else {
            Logger.error("\(TAG) attachment has invalid stream.")
            assert(false)
            return nil
        }
        guard let mediaURL = stream.mediaURL() else {
            Logger.error("\(TAG) attachment missing URL.")
            assert(false)
            return nil
        }
        do {
            let textData = try Data(contentsOf:mediaURL)
            return textData
        } catch {
            Logger.error("\(TAG) error loading data.")
            assert(false)
            return nil
        }
    }

    private func displayText() -> String {
        guard let textData = attachmentData() else {
            Logger.error("\(TAG) could not load attachment data.")
            assert(false)
            return ""
        }
        guard let fullText = String(data:textData, encoding:.utf8) else {
            Logger.error("\(TAG) text is empty.")
            assert(false)
            return ""
        }
        guard let displayText = DisplayableTextFilter().displayableText(fullText) else {
            Logger.error("\(TAG) No valid text.")
            assert(false)
            return ""
        }
        return displayText
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = NSLocalizedString("OVERSIZE_TEXT_MESSAGE_VIEW_TITLE",
                                                      comment: "The title of the 'oversize text message' view.")

        self.view.backgroundColor = UIColor.white

        let textView = UITextView()
        textView.textColor = UIColor.black
        textView.text = displayText()
        textView.font = UIFont.ows_regularFont(withSize:14)
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

        guard let attachment = attachmentStream() else {
            Logger.error("\(TAG) attachment has invalid stream.")
            assert(false)
            return
        }
        
        AttachmentSharing.showShareUI(for:attachment.mediaURL())
    }
}

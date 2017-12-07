//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import MediaPlayer

@objc
public protocol AttachmentApprovalViewControllerDelegate: class {
    func didApproveAttachment()
    func didCancelAttachment()
}

@objc
public class AttachmentApprovalViewController: OWSViewController {

    let TAG = "[AttachmentApprovalViewController]"
    weak var delegate: AttachmentApprovalViewControllerDelegate?

    // MARK: Properties

    let attachment: SignalAttachment

    let mediaMessageView: MediaMessageView

    // MARK: Initializers

    @available(*, unavailable, message:"use attachment: constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("unimplemented")
    }

    required public init(attachment: SignalAttachment, delegate: AttachmentApprovalViewControllerDelegate) {
        assert(!attachment.hasError)
        self.attachment = attachment
        self.delegate = delegate
        self.mediaMessageView = MediaMessageView(attachment: attachment, mode: .large)
        super.init(nibName: nil, bundle: nil)
    }

    // MARK: View Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.white

        createViews()

        self.navigationItem.title = dialogTitle()
    }

    private func dialogTitle() -> String {
        guard let filename = mediaMessageView.formattedFileName() else {
            return NSLocalizedString("ATTACHMENT_APPROVAL_DIALOG_TITLE",
                                     comment: "Title for the 'attachment approval' dialog.")
        }
        return filename
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        mediaMessageView.viewWillAppear(animated)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        mediaMessageView.viewWillDisappear(animated)
    }

    // MARK: - Create Views

    private func createViews() {
        let previewTopMargin: CGFloat = 30
        let previewHMargin: CGFloat = 20

        self.view.addSubview(mediaMessageView)
        mediaMessageView.autoPinWidthToSuperview(withMargin:previewHMargin)
        mediaMessageView.autoPin(toTopLayoutGuideOf: self, withInset:previewTopMargin)

        createButtonRow(mediaMessageView:mediaMessageView)
    }

    private func wrapViewsInVerticalStack(subviews: [UIView]) -> UIView {
        assert(subviews.count > 0)

        let stackView = UIView()

        var lastView: UIView?
        for subview in subviews {

            stackView.addSubview(subview)
            subview.autoHCenterInSuperview()

            if lastView == nil {
                subview.autoPinEdge(toSuperviewEdge:.top)
            } else {
                subview.autoPinEdge(.top, to:.bottom, of:lastView!, withOffset:10)
            }

            lastView = subview
        }

        lastView?.autoPinEdge(toSuperviewEdge:.bottom)

        return stackView
    }

    private func createButtonRow(mediaMessageView: UIView) {
        let buttonTopMargin = ScaleFromIPhone5To7Plus(30, 40)
        let buttonBottomMargin = ScaleFromIPhone5To7Plus(25, 40)
        let buttonHSpacing = ScaleFromIPhone5To7Plus(20, 30)

        let buttonRow = UIView()
        self.view.addSubview(buttonRow)
        buttonRow.autoPinWidthToSuperview()
        buttonRow.autoPinEdge(toSuperviewEdge:.bottom, withInset:buttonBottomMargin)
        buttonRow.autoPinEdge(.top, to:.bottom, of:mediaMessageView, withOffset:buttonTopMargin)

        // We use this invisible subview to ensure that the buttons are centered
        // horizontally.
        let buttonSpacer = UIView()
        buttonRow.addSubview(buttonSpacer)
        // Vertical positioning of this view doesn't matter.
        buttonSpacer.autoPinEdge(toSuperviewEdge:.top)
        buttonSpacer.autoSetDimension(.width, toSize:buttonHSpacing)
        buttonSpacer.autoHCenterInSuperview()

        let cancelButton = createButton(title: CommonStrings.cancelButton,
                                        color : UIColor.ows_destructiveRed(),
                                        action: #selector(cancelPressed))
        buttonRow.addSubview(cancelButton)
        cancelButton.autoPinEdge(toSuperviewEdge:.top)
        cancelButton.autoPinEdge(toSuperviewEdge:.bottom)
        cancelButton.autoPinEdge(.right, to:.left, of:buttonSpacer)

        let sendButton = createButton(title: NSLocalizedString("ATTACHMENT_APPROVAL_SEND_BUTTON",
                                                               comment: "Label for 'send' button in the 'attachment approval' dialog."),
                                      color : UIColor(rgbHex:0x2ecc71),
                                      action: #selector(sendPressed))
        buttonRow.addSubview(sendButton)
        sendButton.autoPinEdge(toSuperviewEdge:.top)
        sendButton.autoPinEdge(toSuperviewEdge:.bottom)
        sendButton.autoPinEdge(.left, to:.right, of:buttonSpacer)
    }

    private func createButton(title: String, color: UIColor, action: Selector) -> UIView {
        let buttonWidth = ScaleFromIPhone5To7Plus(110, 140)
        let buttonHeight = ScaleFromIPhone5To7Plus(35, 45)

        return OWSFlatButton.button(title:title,
                                    titleColor:UIColor.white,
                                    backgroundColor:color,
                                    width:buttonWidth,
                                    height:buttonHeight,
                                    target:target,
                                    selector:action)
    }

    // MARK: - Event Handlers

    func cancelPressed(sender: UIButton) {
        self.delegate?.didCancelAttachment()
    }

    func sendPressed(sender: UIButton) {

        // FIXME
        // this is just a temporary hack to provide some UI
        // until we have a proper progress indicator
        let activityIndicatorView = UIActivityIndicatorView()
        view.addSubview(activityIndicatorView)
        activityIndicatorView.autoCenterInSuperview()
        activityIndicatorView.startAnimating()

        self.delegate?.didApproveAttachment()
    }
}

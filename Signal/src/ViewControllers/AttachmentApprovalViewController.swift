//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import MediaPlayer

class AttachmentApprovalViewController: UIViewController {

    let TAG = "[AttachmentApprovalViewController]"

    // MARK: Properties

    let attachment: SignalAttachment

    var successCompletion : (() -> Void)?

    var videoPlayer: MPMoviePlayerController?

    // MARK: Initializers

    @available(*, unavailable, message:"use attachment: constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        self.attachment = SignalAttachment.genericAttachment(data: nil,
                                                             dataUTI: kUTTypeContent as String)
        super.init(coder: aDecoder)
        assertionFailure()
    }

    required init(attachment: SignalAttachment, successCompletion : @escaping () -> Void) {
        assert(!attachment.hasError)
        self.attachment = attachment
        self.successCompletion = successCompletion
        super.init(nibName: nil, bundle: nil)
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.black

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem:.stop,
            target:self,
            action:#selector(donePressed))
        self.navigationItem.title = NSLocalizedString("ATTACHMENT_APPROVAL_DIALOG_TITLE",
                                                      comment: "Title for the 'attachment approval' dialog.")

        createViews()
    }

    // MARK: - Create Views

    private func createViews() {
        let previewTopMargin: CGFloat = 30
        let previewHMargin: CGFloat = 20

        let attachmentPreviewView = UIView()
        self.view.addSubview(attachmentPreviewView)
        attachmentPreviewView.autoPinWidthToSuperview(withMargin:previewHMargin)
        attachmentPreviewView.autoPin(toTopLayoutGuideOf: self, withInset:previewTopMargin)

        createButtonRow(attachmentPreviewView:attachmentPreviewView)

        if attachment.isAnimatedImage {
            createAnimatedPreview(attachmentPreviewView:attachmentPreviewView)
        } else if attachment.isImage {
            createImagePreview(attachmentPreviewView:attachmentPreviewView)
        } else if attachment.isVideo {
            createVideoPreview(attachmentPreviewView:attachmentPreviewView)
        } else if attachment.isAudio {
            createAudioPreview(attachmentPreviewView:attachmentPreviewView)
        } else {
            createGenericPreview(attachmentPreviewView:attachmentPreviewView)
        }
    }

    private func createAudioPreview(attachmentPreviewView: UIView) {
        // TODO: Add audio player.
        createGenericPreview(attachmentPreviewView:attachmentPreviewView)
    }

    private func createAnimatedPreview(attachmentPreviewView: UIView) {
        // Use Flipboard FLAnimatedImage library to display gifs
        guard let animatedImage = FLAnimatedImage(gifData:attachment.data) else {
            createGenericPreview(attachmentPreviewView:attachmentPreviewView)
            return
        }
        let animatedImageView = FLAnimatedImageView()
        animatedImageView.animatedImage = animatedImage
        animatedImageView.contentMode = .scaleAspectFit
        attachmentPreviewView.addSubview(animatedImageView)
        animatedImageView.autoPinWidthToSuperview()
        animatedImageView.autoPinHeightToSuperview()
    }

    private func createImagePreview(attachmentPreviewView: UIView) {
        var image = attachment.image
        if image == nil {
            image = UIImage(data:attachment.data)
        }
        guard image != nil else {
            createGenericPreview(attachmentPreviewView:attachmentPreviewView)
            return
        }

        let imageView = UIImageView(image:image)
        imageView.layer.minificationFilter = kCAFilterTrilinear
        imageView.layer.magnificationFilter = kCAFilterTrilinear
        imageView.contentMode = .scaleAspectFit
        attachmentPreviewView.addSubview(imageView)
        imageView.autoPinWidthToSuperview()
        imageView.autoPinHeightToSuperview()
    }

    private func createVideoPreview(attachmentPreviewView: UIView) {
        guard let dataUrl = attachment.getTemporaryDataUrl() else {
            createGenericPreview(attachmentPreviewView:attachmentPreviewView)
            return
        }
        guard let videoPlayer = MPMoviePlayerController(contentURL:dataUrl) else {
            createGenericPreview(attachmentPreviewView:attachmentPreviewView)
            return
        }
        videoPlayer.prepareToPlay()

        videoPlayer.controlStyle = .default
        videoPlayer.shouldAutoplay = false

        attachmentPreviewView.addSubview(videoPlayer.view)
        self.videoPlayer = videoPlayer
        videoPlayer.view.autoPinWidthToSuperview()
        videoPlayer.view.autoPinHeightToSuperview()
    }

    private func createGenericPreview(attachmentPreviewView: UIView) {
        let stackView = UIView()
        attachmentPreviewView.addSubview(stackView)
        stackView.autoCenterInSuperview()

        let imageSize = ScaleFromIPhone5To7Plus(175, 225)
        let image = UIImage(named:"file-icon-large")
        assert(image != nil)
        let imageView = UIImageView(image:image)
        imageView.layer.minificationFilter = kCAFilterTrilinear
        imageView.layer.magnificationFilter = kCAFilterTrilinear
        stackView.addSubview(imageView)
        imageView.autoHCenterInSuperview()
        imageView.autoPinEdge(toSuperviewEdge:.top)
        imageView.autoSetDimension(.width, toSize:imageSize)
        imageView.autoSetDimension(.height, toSize:imageSize)

        var lastView: UIView = imageView

        let labelFont = UIFont.ows_regularFont(withSize:ScaleFromIPhone5To7Plus(18, 24))

        if let fileExtension = attachment.fileExtension {
            let fileExtensionLabel = UILabel()
            fileExtensionLabel.text = String(format:NSLocalizedString("ATTACHMENT_APPROVAL_FILE_EXTENSION_FORMAT",
                                                                 comment: "Format string for file extension label in call interstitial view"),
                                             fileExtension.capitalized)

            fileExtensionLabel.textColor = UIColor.white
            fileExtensionLabel.font = labelFont
            fileExtensionLabel.textAlignment = .center
            stackView.addSubview(fileExtensionLabel)
            fileExtensionLabel.autoHCenterInSuperview()
            fileExtensionLabel.autoPinEdge(.top, to:.bottom, of:lastView, withOffset:10)

            lastView = fileExtensionLabel
        }

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = NumberFormatter.Style.decimal
        let fileSizeLabel = UILabel()
        let fileSize = attachment.data.count
        let kOneKilobyte = 1024
        let kOneMegabyte = kOneKilobyte * kOneKilobyte
        let fileSizeText = (fileSize > kOneMegabyte
            ? numberFormatter.string(from: NSNumber(value: fileSize / kOneMegabyte))! + " mb"
            : (fileSize > kOneKilobyte
                ? numberFormatter.string(from: NSNumber(value: fileSize / kOneKilobyte))! + " kb"
                : numberFormatter.string(from: NSNumber(value: fileSize))!))
        fileSizeLabel.text = String(format:NSLocalizedString("ATTACHMENT_APPROVAL_FILE_SIZE_FORMAT",
                                                             comment: "Format string for file size label in call interstitial view"),
                                    fileSizeText)

        fileSizeLabel.textColor = UIColor.white
        fileSizeLabel.font = labelFont
        fileSizeLabel.textAlignment = .center
        stackView.addSubview(fileSizeLabel)
        fileSizeLabel.autoHCenterInSuperview()
        fileSizeLabel.autoPinEdge(.top, to:.bottom, of:lastView, withOffset:10)
        fileSizeLabel.autoPinEdge(toSuperviewEdge:.bottom)
    }

    private func createButtonRow(attachmentPreviewView: UIView) {
        let buttonTopMargin = ScaleFromIPhone5To7Plus(30, 40)
        let buttonBottomMargin = ScaleFromIPhone5To7Plus(25, 40)
        let buttonHSpacing = ScaleFromIPhone5To7Plus(20, 30)

        let buttonRow = UIView()
        self.view.addSubview(buttonRow)
        buttonRow.autoPinWidthToSuperview()
        buttonRow.autoPinEdge(toSuperviewEdge:.bottom, withInset:buttonBottomMargin)
        buttonRow.autoPinEdge(.top, to:.bottom, of:attachmentPreviewView, withOffset:buttonTopMargin)

        // We use this invisible subview to ensure that the buttons are centered
        // horizontally.
        let buttonSpacer = UIView()
        buttonRow.addSubview(buttonSpacer)
        // Vertical positioning of this view doesn't matter.
        buttonSpacer.autoPinEdge(toSuperviewEdge:.top)
        buttonSpacer.autoSetDimension(.width, toSize:buttonHSpacing)
        buttonSpacer.autoHCenterInSuperview()

        let cancelButton = createButton(title: NSLocalizedString("TXT_CANCEL_TITLE",
                                                                 comment: ""),
                                        color : UIColor(rgbHex:0xff3B30),
                                        action: #selector(cancelPressed))
        buttonRow.addSubview(cancelButton)
        cancelButton.autoPinEdge(toSuperviewEdge:.top)
        cancelButton.autoPinEdge(toSuperviewEdge:.bottom)
        cancelButton.autoPinEdge(.right, to:.left, of:buttonSpacer)

        let sendButton = createButton(title: NSLocalizedString("ATTACHMENT_APPROVAL_SEND_BUTTON",
                                                               comment: "Label for 'send' button in the 'attachment approval' dialog."),
                                      color : UIColor(rgbHex:0x4CD964),
                                      action: #selector(sendPressed))
        buttonRow.addSubview(sendButton)
        sendButton.autoPinEdge(toSuperviewEdge:.top)
        sendButton.autoPinEdge(toSuperviewEdge:.bottom)
        sendButton.autoPinEdge(.left, to:.right, of:buttonSpacer)
    }

    private func createButton(title: String, color: UIColor, action: Selector) -> UIButton {
        let buttonFont = UIFont.ows_mediumFont(withSize:ScaleFromIPhone5To7Plus(18, 22))
        let buttonCornerRadius = ScaleFromIPhone5To7Plus(4, 5)
        let buttonWidth = ScaleFromIPhone5To7Plus(110, 140)
        let buttonHeight = ScaleFromIPhone5To7Plus(35, 45)

        let button = UIButton()
        button.setTitle(title, for:.normal)
        button.setTitleColor(UIColor.white, for:.normal)
        button.titleLabel!.font = buttonFont
        button.backgroundColor = color
        button.layer.cornerRadius = buttonCornerRadius
        button.clipsToBounds = true
        button.addTarget(self, action:action, for:.touchUpInside)
        button.autoSetDimension(.width, toSize:buttonWidth)
        button.autoSetDimension(.height, toSize:buttonHeight)
        return button
    }

    // MARK: - Event Handlers

    func donePressed(sender: UIButton) {
        dismiss(animated: true, completion:nil)
    }

    func cancelPressed(sender: UIButton) {
        dismiss(animated: true, completion:nil)
    }

    func sendPressed(sender: UIButton) {
        let successCompletion = self.successCompletion
        dismiss(animated: true, completion: {
            successCompletion?()
        })
    }
}

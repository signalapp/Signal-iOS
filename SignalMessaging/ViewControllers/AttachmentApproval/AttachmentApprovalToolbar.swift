//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

protocol AttachmentApprovalToolbarDelegate: class {
    func attachmentApprovalToolbarUpdateMediaRail()
    func attachmentApprovalToolbarStartEditingCaptions()
    func attachmentApprovalToolbarStopEditingCaptions()
}

// MARK: -

class AttachmentApprovalToolbar: UIView {

    var options: AttachmentApprovalViewControllerOptions {
        didSet {
            attachmentTextToolbar.options = options
        }
    }

    weak var delegate: AttachmentApprovalToolbarDelegate?

    let attachmentTextToolbar: AttachmentTextToolbar
    let attachmentCaptionToolbar: AttachmentCaptionToolbar
    let galleryRailView: GalleryRailView
    let currentCaptionLabel = UILabel()
    let currentCaptionWrapper = UIView()

    var isEditing: Bool {
        return isEditingMediaMessage || attachmentCaptionToolbar.textView.isFirstResponder
    }

    var isEditingMediaMessage: Bool {
        return attachmentTextToolbar.textView.isFirstResponder
    }

    private var isEditingCaptions: Bool = false
    private var currentAttachmentItem: AttachmentApprovalItem?
    public var isApproved: Bool = false

    let kGalleryRailViewHeight: CGFloat = 72

    required init(options: AttachmentApprovalViewControllerOptions, sendButtonImageName: String) {
        self.options = options

        attachmentTextToolbar = AttachmentTextToolbar(options: options, sendButtonImageName: sendButtonImageName)
        attachmentCaptionToolbar = AttachmentCaptionToolbar()

        galleryRailView = GalleryRailView()
        galleryRailView.scrollFocusMode = .keepWithinBounds
        galleryRailView.autoSetDimension(.height, toSize: kGalleryRailViewHeight)

        super.init(frame: .zero)

        createContents()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func createContents() {
        self.backgroundColor = .clear

        // Use a background view that extends below the keyboard to avoid animation glitches.
        let backgroundView = UIView()
        backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        addSubview(backgroundView)
        backgroundView.autoPinWidthToSuperview()
        backgroundView.autoPinEdge(toSuperviewEdge: .top)
        backgroundView.autoPinEdge(toSuperviewEdge: .bottom, withInset: -30)

        currentCaptionLabel.textColor = UIColor(white: 1, alpha: 0.8)
        currentCaptionLabel.font = UIFont.ows_dynamicTypeBody
        currentCaptionLabel.numberOfLines = 5
        currentCaptionLabel.lineBreakMode = .byWordWrapping

        currentCaptionWrapper.isUserInteractionEnabled = true
        currentCaptionWrapper.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(captionTapped)))
        currentCaptionWrapper.addSubview(currentCaptionLabel)
        currentCaptionLabel.autoPinEdgesToSuperviewMargins()

        attachmentCaptionToolbar.attachmentCaptionToolbarDelegate = self

        let stackView = UIStackView(arrangedSubviews: [currentCaptionWrapper, attachmentCaptionToolbar, galleryRailView, attachmentTextToolbar])
        stackView.axis = .vertical

        addSubview(stackView)
        stackView.autoPinEdge(toSuperviewEdge: .top)
        stackView.autoPinEdge(toSuperviewEdge: .leading)
        stackView.autoPinEdge(toSuperviewEdge: .trailing)
        // We pin to the superview's _margin_.  Otherwise the notch breaks
        // the layout if you hide the keyboard in the simulator (or if the
        // user uses an external keyboard).
        stackView.autoPinEdge(toSuperviewMargin: .bottom)
    }

    // MARK: - Events

    @objc func captionTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        delegate?.attachmentApprovalToolbarStartEditingCaptions()
    }

    // MARK: 

    private var shouldHideControls = false

    private func updateContents() {
        var hasCurrentCaption = false
        if let currentAttachmentItem = currentAttachmentItem,
            let captionText = currentAttachmentItem.captionText {
            hasCurrentCaption = captionText.count > 0

            attachmentCaptionToolbar.textView.text = captionText
            currentCaptionLabel.text = captionText
        } else {
            attachmentCaptionToolbar.textView.text = nil
            currentCaptionLabel.text = nil
        }

        attachmentCaptionToolbar.isHidden = !isEditingCaptions
        currentCaptionWrapper.isHidden = isEditingCaptions || !hasCurrentCaption
        attachmentTextToolbar.isHidden = isEditingCaptions || isApproved
        attachmentTextToolbar.isUserInteractionEnabled = !isApproved

        updateFirstResponder()

        layoutSubviews()
    }

    override func resignFirstResponder() -> Bool {
        if attachmentCaptionToolbar.textView.isFirstResponder {
            return attachmentCaptionToolbar.textView.resignFirstResponder()
        } else if attachmentTextToolbar.textView.isFirstResponder {
            return attachmentTextToolbar.textView.resignFirstResponder()
        } else {
            return super.resignFirstResponder()
        }
    }

    private func updateFirstResponder() {
        if shouldHideControls {
            if attachmentCaptionToolbar.textView.isFirstResponder {
                attachmentCaptionToolbar.textView.resignFirstResponder()
            } else if attachmentTextToolbar.textView.isFirstResponder {
                attachmentTextToolbar.textView.resignFirstResponder()
            }
        } else if isEditingCaptions {
            // While editing captions, the keyboard should always remain visible.
            if !attachmentCaptionToolbar.textView.isFirstResponder {
                attachmentCaptionToolbar.textView.becomeFirstResponder()
            }
        } else {
            if attachmentCaptionToolbar.textView.isFirstResponder {
                attachmentCaptionToolbar.textView.resignFirstResponder()
            }
        }
        // NOTE: We don't automatically make attachmentTextToolbar.textView
        // first responder;
    }

    public func update(isEditingCaptions: Bool,
                       currentAttachmentItem: AttachmentApprovalItem?,
                       shouldHideControls: Bool,
                       isApproved: Bool,
                       recipientNames: [String]) {
        // De-bounce
        guard self.isEditingCaptions != isEditingCaptions ||
            self.currentAttachmentItem != currentAttachmentItem ||
            self.shouldHideControls != shouldHideControls ||
            self.isApproved != isApproved else {

                updateFirstResponder()
                return
        }

        self.isEditingCaptions = isEditingCaptions
        self.currentAttachmentItem = currentAttachmentItem
        self.shouldHideControls = shouldHideControls
        self.isApproved = isApproved

        self.attachmentTextToolbar.recipientNames = recipientNames

        updateContents()
    }

    // MARK: 

    override var intrinsicContentSize: CGSize {
        get {
            // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
            // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
            return CGSize.zero
        }
    }

    public var hasFirstResponder: Bool {
        return (isFirstResponder ||
            attachmentCaptionToolbar.textView.isFirstResponder ||
            attachmentTextToolbar.textView.isFirstResponder)
    }
}

// MARK: -

extension AttachmentApprovalToolbar: AttachmentCaptionToolbarDelegate {
    public func attachmentCaptionToolbarDidEdit(_ attachmentCaptionToolbar: AttachmentCaptionToolbar) {
        guard let currentAttachmentItem = currentAttachmentItem else {
            owsFailDebug("Missing currentAttachmentItem.")
            return
        }

        currentAttachmentItem.attachment.captionText = attachmentCaptionToolbar.textView.text

        delegate?.attachmentApprovalToolbarUpdateMediaRail()
    }

    public func attachmentCaptionToolbarDidComplete() {
        delegate?.attachmentApprovalToolbarStopEditingCaptions()
    }
}

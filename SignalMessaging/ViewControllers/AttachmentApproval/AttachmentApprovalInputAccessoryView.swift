//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

protocol AttachmentApprovalInputAccessoryViewDelegate: class {
    func attachmentApprovalInputUpdateMediaRail()
    func attachmentApprovalInputEditCaptions()
}

// MARK: -

class AttachmentApprovalInputAccessoryView: UIView {

    weak var delegate: AttachmentApprovalInputAccessoryViewDelegate?

    let attachmentTextToolbar: AttachmentTextToolbar
    let attachmentCaptionToolbar: AttachmentCaptionToolbar
    let galleryRailView: GalleryRailView
    let currentCaptionLabel = UILabel()
    let currentCaptionWrapper = UIView()

    var isEditingMediaMessage: Bool {
        return attachmentTextToolbar.textView.isFirstResponder
    }

    private var isEditingCaptions: Bool = false
    private var currentAttachmentItem: SignalAttachmentItem?

    let kGalleryRailViewHeight: CGFloat = 72

    required init(isAddMoreVisible: Bool) {
        attachmentTextToolbar = AttachmentTextToolbar(isAddMoreVisible: isAddMoreVisible)

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
        // Specifying auto-resizing mask and an intrinsic content size allows proper
        // sizing when used as an input accessory view.
        self.autoresizingMask = .flexibleHeight
        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = .clear

        preservesSuperviewLayoutMargins = true

        // Use a background view that extends below the keyboard to avoid animation glitches.
        let backgroundView = UIView()
        backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        addSubview(backgroundView)
        backgroundView.autoPinEdge(toSuperviewEdge: .top)
        backgroundView.autoPinEdge(toSuperviewEdge: .leading)
        backgroundView.autoPinEdge(toSuperviewEdge: .trailing)
        backgroundView.autoPinEdge(toSuperviewEdge: .bottom, withInset: -200)

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
        stackView.autoPinEdgesToSuperviewEdges()
    }

    // MARK: - Events

    @objc func captionTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        delegate?.attachmentApprovalInputEditCaptions()
    }

    // MARK: 

    public var shouldHideControls = false {
        didSet {
            updateContents()
        }
    }

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
        attachmentTextToolbar.isHidden = isEditingCaptions

        if (shouldHideControls) {
            if attachmentCaptionToolbar.textView.isFirstResponder {
                attachmentCaptionToolbar.textView.resignFirstResponder()
            } else if attachmentTextToolbar.textView.isFirstResponder {
                attachmentTextToolbar.textView.resignFirstResponder()
            }
        } else if (isEditingCaptions) {
            // While editing captions, the keyboard should always remain visible.
            if !attachmentCaptionToolbar.textView.isFirstResponder {
                attachmentCaptionToolbar.textView.becomeFirstResponder()
            }
        }
        // NOTE: We don't automatically make attachmentTextToolbar.textView
        // first responder;

        layoutSubviews()
    }

    public func update(isEditingCaptions: Bool,
                       currentAttachmentItem: SignalAttachmentItem?) {
        self.isEditingCaptions = isEditingCaptions
        self.currentAttachmentItem = currentAttachmentItem

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
}

// MARK: -

extension AttachmentApprovalInputAccessoryView: AttachmentCaptionToolbarDelegate {
    public func attachmentCaptionToolbarDidEdit(_ attachmentCaptionToolbar: AttachmentCaptionToolbar) {
        guard let currentAttachmentItem = currentAttachmentItem else {
            owsFailDebug("Missing currentAttachmentItem.")
            return
        }

        currentAttachmentItem.attachment.captionText = attachmentCaptionToolbar.textView.text

        delegate?.attachmentApprovalInputUpdateMediaRail()
    }
}

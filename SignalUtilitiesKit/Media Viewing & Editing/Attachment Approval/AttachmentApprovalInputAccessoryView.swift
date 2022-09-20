// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import UIKit
import SessionUIKit

protocol AttachmentApprovalInputAccessoryViewDelegate: AnyObject {
    func attachmentApprovalInputUpdateMediaRail()
    func attachmentApprovalInputStartEditingCaptions()
    func attachmentApprovalInputStopEditingCaptions()
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

    required init() {
        attachmentTextToolbar = AttachmentTextToolbar()
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
        self.themeBackgroundColor = .clear

        preservesSuperviewLayoutMargins = true

        // Use a background view that extends below the keyboard to avoid animation glitches.
        let backgroundView = UIView()
        backgroundView.themeBackgroundColor = .backgroundPrimary
        addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()

        currentCaptionLabel.themeTextColor = .white
        currentCaptionLabel.font = .systemFont(ofSize: Values.mediumFontSize)
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
        
        let galleryRailBlockingView: UIView = UIView()
        galleryRailBlockingView.themeBackgroundColor = .backgroundPrimary
        stackView.addSubview(galleryRailBlockingView)
        galleryRailBlockingView.pin(.top, to: .bottom, of: attachmentTextToolbar)
        galleryRailBlockingView.pin(.left, to: .left, of: stackView)
        galleryRailBlockingView.pin(.right, to: .right, of: stackView)
        galleryRailBlockingView.pin(.bottom, to: .bottom, of: stackView)
    }

    // MARK: - Events

    @objc func captionTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else { return }
        
        delegate?.attachmentApprovalInputStartEditingCaptions()
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
        attachmentTextToolbar.isHidden = isEditingCaptions

        updateFirstResponder()

        layoutSubviews()
    }

    private func updateFirstResponder() {
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
        } else {
            if attachmentCaptionToolbar.textView.isFirstResponder {
                attachmentCaptionToolbar.textView.resignFirstResponder()
            }
        }
        // NOTE: We don't automatically make attachmentTextToolbar.textView
        // first responder;
    }

    public func update(isEditingCaptions: Bool,
                       currentAttachmentItem: SignalAttachmentItem?,
                       shouldHideControls: Bool) {
        // De-bounce
        guard self.isEditingCaptions != isEditingCaptions ||
            self.currentAttachmentItem != currentAttachmentItem ||
            self.shouldHideControls != shouldHideControls else {

                updateFirstResponder()
                return
        }

        self.isEditingCaptions = isEditingCaptions
        self.currentAttachmentItem = currentAttachmentItem
        self.shouldHideControls = shouldHideControls

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

extension AttachmentApprovalInputAccessoryView: AttachmentCaptionToolbarDelegate {
    public func attachmentCaptionToolbarDidEdit(_ attachmentCaptionToolbar: AttachmentCaptionToolbar) {
        guard let currentAttachmentItem = currentAttachmentItem else {
            owsFailDebug("Missing currentAttachmentItem.")
            return
        }

        // TODO: Look at refactoring this behaviour to consolidate attachment mutations
        currentAttachmentItem.attachment.captionText = attachmentCaptionToolbar.textView.text

        delegate?.attachmentApprovalInputUpdateMediaRail()
    }

    public func attachmentCaptionToolbarDidComplete() {
        delegate?.attachmentApprovalInputStopEditingCaptions()
    }
}

//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import UIKit

class AttachmentApprovalToolbar: UIView {

    struct Configuration: Equatable {
        var isAddMoreVisible = true
        var isMediaStripVisible = false
        var isMediaHighQualityEnabled = false
        var isViewOnceOn = false
        var canToggleViewOnce = true
        var canChangeMediaQuality = true
        var canSaveMedia = false
        var doneButtonIcon: DoneButtonIcon = .send

        enum DoneButtonIcon: String {
            case send = "send-blue-42-dark"
            case next = "chevron-right-colored-42"
        }
    }

    var configuration: Configuration

    // Only visible when there's one media item and contains "Add Media" and "View Once" buttons.
    // Displayed in place of galleryRailView.
    private lazy var singleMediaActionButtonsContainer: UIView = {
        let view = UIView()
        view.preservesSuperviewLayoutMargins = true
        view.layoutMargins.bottom = 0

        view.addSubview(buttonAddMedia)
        buttonAddMedia.autoPinHeightToSuperviewMargins()
        buttonAddMedia.layoutMarginsGuide.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor).isActive = true

        view.addSubview(buttonViewOnce)
        buttonViewOnce.autoPinHeightToSuperviewMargins()
        buttonViewOnce.layoutMarginsGuide.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor).isActive = true

        return view
    }()
    let buttonAddMedia: UIButton = RoundMediaButton(
        image: UIImage(imageLiteralResourceName: "plus-square-28"),
        backgroundStyle: .blur
    )
    let buttonViewOnce: UIButton = RoundMediaButton(
        image: UIImage(imageLiteralResourceName: "view_once-28"),
        backgroundStyle: .blur
    )
    // Contains message input field and a button to finish editing.
    let attachmentTextToolbar: AttachmentTextToolbar
    weak var attachmentTextToolbarDelegate: AttachmentTextToolbarDelegate?
    // Shows previews of media object.
    let galleryRailView: GalleryRailView
    // Row of buttons at the bottom of the screen.
    private let mediaToolbar = MediaToolbar()

    private lazy var opaqueContentView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [ attachmentTextToolbar, mediaToolbar ])
        stackView.axis = .vertical
        stackView.preservesSuperviewLayoutMargins = true
        return stackView
    }()

    private lazy var containerStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [ opaqueContentView ])
        stackView.axis = .vertical
        stackView.preservesSuperviewLayoutMargins = true
        return stackView
    }()

    private var viewOnceTooltip: UIView?

    var isEditingMediaMessage: Bool {
        return attachmentTextToolbar.isEditingText
    }

    private var currentAttachmentItem: AttachmentApprovalItem?

    override init(frame: CGRect) {
        configuration = Configuration()

        attachmentTextToolbar = AttachmentTextToolbar()
        attachmentTextToolbar.setIsViewOnce(enabled: configuration.isViewOnceOn, animated: false)

        galleryRailView = GalleryRailView()
        galleryRailView.itemSize = 44
        galleryRailView.scrollFocusMode = .keepWithinBounds

        super.init(frame: frame)

        createContents()
    }

    @available(*, unavailable, message: "Use init(frame:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func createContents() {
        backgroundColor = .clear
        layoutMargins.bottom = 0
        preservesSuperviewLayoutMargins = true

        attachmentTextToolbar.delegate = self

        addSubview(galleryRailView)
        galleryRailView.autoPinWidthToSuperview()
        galleryRailView.autoPinEdge(toSuperviewEdge: .top)

        addSubview(singleMediaActionButtonsContainer)
        singleMediaActionButtonsContainer.autoPinWidthToSuperview()
        singleMediaActionButtonsContainer.autoPinEdge(.bottom, to: .bottom, of: galleryRailView)

        // Use a background view that extends below the keyboard to avoid animation glitches.
        let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        addSubview(backgroundView)
        backgroundView.autoPinWidthToSuperview()
        backgroundView.autoPinEdge(.top, to: .bottom, of: galleryRailView)
        backgroundView.autoPinEdge(toSuperviewEdge: .bottom, withInset: -30)

        addSubview(containerStackView)
        containerStackView.autoPinEdge(.top, to: .bottom, of: galleryRailView)
        containerStackView.autoPinWidthToSuperview()
        // We pin to the superview's _margin_.  Otherwise the notch breaks
        // the layout if you hide the keyboard in the simulator (or if the
        // user uses an external keyboard).
        containerStackView.autoPinEdge(toSuperviewMargin: .bottom)
    }

    private var supplementaryViewContainer: UIView?
    func set(supplementaryView: UIView?) {
        if let supplementaryViewContainer = supplementaryViewContainer {
            supplementaryViewContainer.removeFromSuperview()
            containerStackView.removeArrangedSubview(supplementaryViewContainer)
            self.supplementaryViewContainer = nil
        }
        guard let supplementaryView = supplementaryView else {
            return
        }

        let containerView = UIView()
        containerView.preservesSuperviewLayoutMargins = true
        containerView.addSubview(supplementaryView)
        supplementaryView.autoPinEdgesToSuperviewMargins()
        containerStackView.insertArrangedSubview(containerView, at: 0)
        self.supplementaryViewContainer = containerView
    }

    var opaqueAreaHeight: CGFloat { opaqueContentView.height }

    // MARK: 

    private func updateContents(animated: Bool) {
        // Show/hide Gallery Rail.
        let isGalleryRailViewVisible = configuration.isMediaStripVisible && !isEditingMediaMessage
        galleryRailView.setIsHidden(!isGalleryRailViewVisible, animated: animated)

        // Show/hide [+] Add Media button and "View Once" toggle.
        let isSingleMediaActionsVisible = !configuration.isMediaStripVisible && !isEditingMediaMessage
        singleMediaActionButtonsContainer.setIsHidden(!isSingleMediaActionsVisible, animated: animated)

        // [+] Add Media might also be hidden independently of Media Rail and View Once.
        buttonAddMedia.setIsHidden(!configuration.isAddMoreVisible, animated: animated)

        // Update image and visibility of the "View Once" button.
        let viewOnceButtonImage = UIImage(imageLiteralResourceName: configuration.isViewOnceOn ? "view_once-28" : "view_once-infinite-28")
        buttonViewOnce.setImage(viewOnceButtonImage, animated: animated)
        buttonViewOnce.setIsHidden(!configuration.canToggleViewOnce, animated: animated)

        supplementaryViewContainer?.isHiddenInStackView = isEditingMediaMessage

        attachmentTextToolbar.setIsViewOnce(enabled: configuration.isViewOnceOn, animated: animated)

        // Visibility of bottom buttons only changes when user starts/finishes composing text message.
        // In that case `updateContents(animated:)` is called from within an animation block
        // and since `mediaToolbar` is in a stack view it is necessary to modify `isHiddenInStackView`
        // to get a nice animation.
        mediaToolbar.isHiddenInStackView = isEditingMediaMessage

        mediaToolbar.sendButton.setImage(UIImage(imageLiteralResourceName: configuration.doneButtonIcon.rawValue), for: .normal)
        mediaToolbar.setIsMediaQualityHigh(enabled: configuration.isMediaHighQualityEnabled, animated: animated)

        let availableButtons: MediaToolbar.AvailableButtons = {
            guard let currentAttachmentItem = currentAttachmentItem else {
                return []
            }
            var buttons: MediaToolbar.AvailableButtons = []
            if configuration.canSaveMedia {
                buttons.insert(.save)
            }
            if configuration.canChangeMediaQuality {
                buttons.insert(.mediaQuality)
            }
            switch currentAttachmentItem.type {
            case .image:
                buttons.insert(.pen)
                buttons.insert(.crop)

            default:
                break
            }
            return buttons
        }()
        mediaToolbar.set(availableButtons: availableButtons, animated: animated)

        updateFirstResponder()

        showViewOnceTooltipIfNecessary()
    }

    override func resignFirstResponder() -> Bool {
        if isEditingMediaMessage {
            return attachmentTextToolbar.textView.resignFirstResponder()
        } else {
            return super.resignFirstResponder()
        }
    }

    private func updateFirstResponder() {
        if configuration.isViewOnceOn {
            if isEditingMediaMessage {
                _ = attachmentTextToolbar.textView.resignFirstResponder()
            }
        }
        // NOTE: We don't automatically make attachmentTextToolbar.textView
        // first responder;
    }

    func update(currentAttachmentItem: AttachmentApprovalItem,
                configuration: Configuration,
                animated: Bool) {
        // De-bounce
        guard self.currentAttachmentItem != currentAttachmentItem || self.configuration != configuration else {
            updateFirstResponder()
            return
        }

        self.currentAttachmentItem = currentAttachmentItem
        self.configuration = configuration

        updateContents(animated: animated)
    }

    // MARK: 

    // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
    // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
    override var intrinsicContentSize: CGSize { .zero }

    public var hasFirstResponder: Bool {
        return (isFirstResponder || attachmentTextToolbar.textView.isFirstResponder)
    }
}

extension AttachmentApprovalToolbar: AttachmentTextToolbarDelegate {

    func attachmentTextToolbarWillBeginEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        attachmentTextToolbarDelegate?.attachmentTextToolbarWillBeginEditing(attachmentTextToolbar)
    }

    func attachmentTextToolbarDidBeginEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        updateContents(animated: true)
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidBeginEditing(attachmentTextToolbar)
    }

    func attachmentTextToolbarDidEndEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        updateContents(animated: true)
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidEndEditing(attachmentTextToolbar)
    }

    func attachmentTextToolbarDidChange(_ attachmentTextToolbar: AttachmentTextToolbar) {
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidChange(attachmentTextToolbar)
    }

    func attachmentTextToolBarDidChangeHeight(_ attachmentTextToolbar: AttachmentTextToolbar) {
        setNeedsLayout()
        layoutIfNeeded()
    }
}

// MARK: - View Once Tooltip

extension AttachmentApprovalToolbar {

    // The tooltip lies outside this view's bounds, so we
    // need to special-case the hit testing so that it can
    // intercept touches within its bounds.
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let viewOnceTooltip = self.viewOnceTooltip {
            let tooltipFrame = convert(viewOnceTooltip.bounds, from: viewOnceTooltip)
            if tooltipFrame.contains(point) {
                return true
            }
        }
        return super.point(inside: point, with: event)
    }

    private var shouldShowViewOnceTooltip: Bool {
        guard !configuration.isMediaStripVisible else {
            return false
        }
        guard !configuration.isViewOnceOn && configuration.canToggleViewOnce else {
            return false
        }
        guard !preferences.wasViewOnceTooltipShown else {
            return false
        }
        return true
    }

    // Show the tooltip if a) it should be shown b) isn't already showing.
    private func showViewOnceTooltipIfNecessary() {
        guard shouldShowViewOnceTooltip else {
            return
        }
        guard nil == viewOnceTooltip else {
            // Already showing the tooltip.
            return
        }
        let tooltip = ViewOnceTooltip.present(fromView: self, widthReferenceView: self, tailReferenceView: buttonViewOnce) { [weak self] in
            self?.removeViewOnceTooltip()
        }
        viewOnceTooltip = tooltip

        DispatchQueue.global().async {
            self.preferences.setWasViewOnceTooltipShown()

            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 5) { [weak self] in
                self?.removeViewOnceTooltip()
            }
        }
    }

    private func removeViewOnceTooltip() {
        viewOnceTooltip?.removeFromSuperview()
        viewOnceTooltip = nil
    }

}

// MARK: - Bottom Row Buttons

extension AttachmentApprovalToolbar {

    var buttonSend: UIButton {
        mediaToolbar.sendButton
    }

    var buttonMediaQuality: UIButton {
        mediaToolbar.mediaQualityButton
    }

    var buttonSaveMedia: UIButton {
        mediaToolbar.saveMediaButton
    }

    var buttonPenTool: UIButton {
        mediaToolbar.penToolButton
    }

    var buttonCropTool: UIButton {
        mediaToolbar.cropToolButton
    }
}

private class MediaToolbar: UIView {

    struct AvailableButtons: OptionSet {
        let rawValue: Int

        static let pen  = AvailableButtons(rawValue: 1 << 0)
        static let crop = AvailableButtons(rawValue: 1 << 1)
        static let save = AvailableButtons(rawValue: 1 << 2)
        static let mediaQuality = AvailableButtons(rawValue: 1 << 3)

        static let all: AvailableButtons = [ .pen, .crop, .save, .mediaQuality ]
    }

    func set(availableButtons: AvailableButtons, animated: Bool) {
        penToolButton.setIsHidden(!availableButtons.contains(.pen), animated: animated)
        cropToolButton.setIsHidden(!availableButtons.contains(.crop), animated: animated)
        saveMediaButton.setIsHidden(!availableButtons.contains(.save), animated: animated)
        mediaQualityButton.setIsHidden(!availableButtons.contains(.mediaQuality), animated: animated)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true

        let stackView = UIStackView(arrangedSubviews: [ penToolButton, cropToolButton, mediaQualityButton,
                                                        saveMediaButton, UIView.transparentSpacer(), sendButton ])
        stackView.spacing = 4
        addSubview(stackView)
        stackView.autoPinLeadingToSuperviewMargin(withInset: -penToolButton.layoutMargins.leading)
        sendButton.layoutMarginsGuide.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true
        stackView.autoPinEdge(toSuperviewEdge: .top)
        stackView.autoPinEdge(toSuperviewEdge: .bottom, withInset: UIDevice.current.hasIPhoneXNotch ? 0 : 8)

        stackView.arrangedSubviews.compactMap { $0 as? UIButton }.forEach { button in
            button.setCompressionResistanceHigh()
        }
    }

    @available(*, unavailable, message: "Use init(frame:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    static private let buttonBackgroundColor = RoundMediaButton.defaultBackgroundColor
    let penToolButton: UIButton = RoundMediaButton(
        image: UIImage(imageLiteralResourceName: "brush-pen-28"),
        backgroundStyle: .solid(buttonBackgroundColor)
    )
    let cropToolButton: UIButton = RoundMediaButton(
        image: UIImage(imageLiteralResourceName: "crop-rotate-28"),
        backgroundStyle: .solid(buttonBackgroundColor)
    )
    lazy var mediaQualityButton: UIButton = RoundMediaButton(
        image: MediaToolbar.imageMediaQualityStandard,
        backgroundStyle: .solid(MediaToolbar.buttonBackgroundColor)
    )
    let saveMediaButton: UIButton = RoundMediaButton(
        image: UIImage(imageLiteralResourceName: "save-28"),
        backgroundStyle: .solid(buttonBackgroundColor)
    )
    let sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(imageLiteralResourceName: AttachmentApprovalToolbar.Configuration.DoneButtonIcon.send.rawValue),
            for: .normal
        )
        button.contentEdgeInsets = UIEdgeInsets(margin: UIDevice.current.isNarrowerThanIPhone6 ? 4 : 8)
        button.accessibilityLabel = MessageStrings.sendButton
        button.sizeToFit()
        return button
    }()

    private static let imageMediaQualityHigh = UIImage(imageLiteralResourceName: "quality-high")
    private static let imageMediaQualityStandard = UIImage(imageLiteralResourceName: "quality-standard")

    fileprivate func setIsMediaQualityHigh(enabled: Bool, animated: Bool) {
        let image = enabled ? MediaToolbar.imageMediaQualityHigh : MediaToolbar.imageMediaQualityStandard
        mediaQualityButton.setImage(image, animated: animated)
    }
}

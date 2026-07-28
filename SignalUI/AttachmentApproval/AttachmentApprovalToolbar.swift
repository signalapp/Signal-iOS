//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

class AttachmentApprovalToolbar: UIView, MediaCaptionToolbarDelegate {

    struct Configuration: Equatable {
        var isAddMoreVisible = true
        var isMediaStripVisible = false
        var isMediaHighQualityEnabled = false
        var isViewOnceOn = false
        var canToggleViewOnce = true
        var canChangeMediaQuality = true
        var canSaveMedia = false
        var proceedButtonIcon: ProceedButtonIcon = .send

        enum ProceedButtonIcon: String {
            case send = "arrow-up"
            case next = "chevron-right-26"
        }
    }

    var configuration = Configuration()

    let contentLayoutGuide = UILayoutGuide()

    weak var captionToolbarDelegate: MediaCaptionToolbarDelegate?

    // Top row: previews of media items. Only shown when there are multiple.
    lazy var galleryRailView: GalleryRailView = {
        let galleryRailView = GalleryRailView()
        galleryRailView.itemSize = 44
        if #available(iOS 26, *) {
            // Increase spacing above `mediaToolbar` from default `8`.
            // Pre-iOS 26 keeps default `8` as padding above the blurred background.
            galleryRailView.layoutMargins.bottom = 16
        } else {
            galleryRailView.scrollFocusMode = .keepWithinBounds
        }
        return galleryRailView
    }()

    // Middle row: tool bar with buttons.
    private let mediaToolbar = MediaToolbar()
    // Bottom row: caption input field with the Send button.
    lazy var mediaCaptionToolbar: MediaCaptionToolbar = {
        let toolbar = MediaCaptionToolbar()
        toolbar.setIsViewOnce(
            enabled: configuration.canToggleViewOnce,
            on: configuration.isViewOnceOn,
            animated: false,
        )
        toolbar.delegate = self
        return toolbar
    }()

    private lazy var opaqueContentView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [mediaToolbar, mediaCaptionToolbar])
        stackView.axis = .vertical
        // Both `mediaToolbar` and `mediaCaptionToolbar` have 8 dp of vertical margins in them.
        // iOS 26 needs more space - 24dp - between rows.
        stackView.spacing = if #available(iOS 26, *) { 8 } else { 0 }
        return stackView
    }()

    private lazy var containerStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [opaqueContentView])
        stackView.axis = .vertical
        // Each row of controls has 8dp vertical margins.
        // iOS 26 needs more space - 24dp - between rows.
        stackView.spacing = if #available(iOS 26, *) { 8 } else { 0 }
        return stackView
    }()

    var isEditingCaptionText: Bool {
        return mediaCaptionToolbar.isEditingText
    }

    private var currentAttachmentItem: AttachmentApprovalItem?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        tintColor = .Signal.label
        preservesSuperviewLayoutMargins = true

        // View controller will use this layout guide to position UI elements above the keyboard.
        addLayoutGuide(contentLayoutGuide)
        NSLayoutConstraint.activate([
            contentLayoutGuide.topAnchor.constraint(equalTo: topAnchor),
            contentLayoutGuide.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentLayoutGuide.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentLayoutGuide.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])

        // Thumbnail strip is positioned above the protection background (pre-iOS 26), directly over media.
        addSubview(galleryRailView)
        galleryRailView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            galleryRailView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            galleryRailView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            galleryRailView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
        ])

        // Pre-iOS 26 has blur background underneath caption input field and buttons.
        containerStackView.translatesAutoresizingMaskIntoConstraints = false
        if #unavailable(iOS 26) {
            let blurBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
            blurBackgroundView.translatesAutoresizingMaskIntoConstraints = false
            blurBackgroundView.contentView.addSubview(containerStackView)
            addSubview(blurBackgroundView)
            NSLayoutConstraint.activate([
                blurBackgroundView.topAnchor.constraint(equalTo: galleryRailView.bottomAnchor),
                blurBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
                blurBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
                blurBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

                containerStackView.topAnchor.constraint(equalTo: blurBackgroundView.topAnchor),
                containerStackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
                containerStackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
                containerStackView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            ])
        } else {
            addSubview(containerStackView)
            NSLayoutConstraint.activate([
                containerStackView.topAnchor.constraint(equalTo: galleryRailView.bottomAnchor),
                containerStackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
                containerStackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
                containerStackView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var supplementaryViewContainer: UIView?

    func set(supplementaryView: UIView?) {
        if let supplementaryViewContainer {
            supplementaryViewContainer.removeFromSuperview()
            containerStackView.removeArrangedSubview(supplementaryViewContainer)
            self.supplementaryViewContainer = nil
        }
        guard let supplementaryView else {
            return
        }

        let containerView = UIView()
        supplementaryView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(supplementaryView)
        let topMargin: CGFloat = if #available(iOS 26, *) { 0 } else { 16 }
        let bottomMargin: CGFloat = if #available(iOS 26, *) { 8 } else { 0 }
        NSLayoutConstraint.activate([
            supplementaryView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: topMargin),
            supplementaryView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            supplementaryView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            supplementaryView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -bottomMargin),
        ])
        containerStackView.insertArrangedSubview(containerView, at: 0)
        self.supplementaryViewContainer = containerView
    }

    var opaqueAreaHeight: CGFloat { opaqueContentView.height }

    private func updateContents(animated: Bool) {
        // Show/hide Gallery Rail.
        let isGalleryRailViewVisible = configuration.isMediaStripVisible && !isEditingCaptionText
        galleryRailView.setIsHidden(!isGalleryRailViewVisible, animated: animated)

        supplementaryViewContainer?.isHiddenInStackView = isEditingCaptionText

        mediaToolbar.setIsMediaQualityHigh(
            enabled: configuration.isMediaHighQualityEnabled,
            animated: animated,
        )
        let availableButtons: MediaToolbar.AvailableButtons = {
            guard let currentAttachmentItem else {
                return []
            }
            var buttons: MediaToolbar.AvailableButtons = []
            if configuration.canSaveMedia {
                buttons.insert(.save)
            }
            if configuration.canChangeMediaQuality {
                buttons.insert(.mediaQuality)
            }
            if configuration.isAddMoreVisible {
                buttons.insert(.addMedia)
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

        // Visibility of bottom buttons only changes when user starts/finishes composing text message.
        // In that case `updateContents(animated:)` is called from within an animation block
        // and since `mediaToolbar` is in a stack view it is necessary to modify `isHiddenInStackView`
        // to get a nice animation.
        mediaToolbar.isHiddenInStackView = isEditingCaptionText || availableButtons.isEmpty

        mediaCaptionToolbar.setProceedButtonImage(
            UIImage(imageLiteralResourceName: configuration.proceedButtonIcon.rawValue),
        )
        mediaCaptionToolbar.setIsViewOnce(
            enabled: configuration.canToggleViewOnce,
            on: configuration.isViewOnceOn,
            animated: animated,
        )

        showViewOnceTooltipIfNecessary()
    }

    func update(currentAttachmentItem: AttachmentApprovalItem, configuration: Configuration, animated: Bool) {
        // De-bounce
        if currentAttachmentItem.isIdenticalTo(self.currentAttachmentItem as AttachmentApprovalItem?), self.configuration == configuration {
            return
        }

        self.currentAttachmentItem = currentAttachmentItem
        self.configuration = configuration

        updateContents(animated: animated)
    }

    func finishTextEditing() {
        mediaCaptionToolbar.finishTextEditing()
    }

    // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
    // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
    override var intrinsicContentSize: CGSize { .zero }

    // MARK: - AttachmentTextToolbarDelegate

    func mediaCaptionToolbarWillBeginEditing(_ mediaCaptionToolbar: MediaCaptionToolbar) {
        captionToolbarDelegate?.mediaCaptionToolbarWillBeginEditing(mediaCaptionToolbar)
    }

    func mediaCaptionToolbarDidBeginEditing(_ mediaCaptionToolbar: MediaCaptionToolbar) {
        updateContents(animated: true)
        captionToolbarDelegate?.mediaCaptionToolbarDidBeginEditing(mediaCaptionToolbar)
    }

    func mediaCaptionToolbarDidEndEditing(_ mediaCaptionToolbar: MediaCaptionToolbar) {
        updateContents(animated: true)
        captionToolbarDelegate?.mediaCaptionToolbarDidEndEditing(mediaCaptionToolbar)
    }

    func mediaCaptionToolbarDidChangeText(_ mediaCaptionToolbar: MediaCaptionToolbar) {
        captionToolbarDelegate?.mediaCaptionToolbarDidChangeText(mediaCaptionToolbar)
    }

    func mediaCaptionToolBarDidChangeHeight(_ mediaCaptionToolbar: MediaCaptionToolbar) {
        setNeedsLayout()
        layoutIfNeeded()
    }

    // MARK: - View Once Tooltip

    private var viewOnceTooltip: UIView?

    // The tooltip lies outside this view's bounds, so we
    // need to special-case the hit testing so that it can
    // intercept touches within its bounds.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
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
        guard !configuration.isViewOnceOn, configuration.canToggleViewOnce else {
            return false
        }
        guard !SSKEnvironment.shared.preferencesRef.wasViewOnceTooltipShown else {
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
        let tooltip = ViewOnceTooltip.present(
            fromView: self,
            widthReferenceView: self,
            tailReferenceView: mediaCaptionToolbar.viewOnceButton,
        ) { [weak self] in
            self?.removeViewOnceTooltip()
        }
        viewOnceTooltip = tooltip

        DispatchQueue.global().async {
            SSKEnvironment.shared.preferencesRef.setWasViewOnceTooltipShown()

            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 5) { [weak self] in
                self?.removeViewOnceTooltip()
            }
        }
    }

    private func removeViewOnceTooltip() {
        viewOnceTooltip?.removeFromSuperview()
        viewOnceTooltip = nil
    }

    // MARK: - Buttons

    var buttonProceed: UIButton {
        mediaCaptionToolbar.proceedButton
    }

    var buttonViewOnce: UIButton {
        let viewOnceButton = mediaCaptionToolbar.viewOnceButton
        viewOnceButton.accessibilityLabel = OWSLocalizedString(
            "ATTACHMENT_TOOL_BUTTON_VIEW_ONE_ACCESSIBILITY_LABEL",
            comment: "Accessibility label for the 'view one' dialog.",
        )
        return viewOnceButton
    }

    var buttonPenTool: UIButton {
        let penToolButton = mediaToolbar.penToolButton
        penToolButton.accessibilityLabel = OWSLocalizedString(
            "ATTACHMENT_TOOL_BUTTON_PEN_ACCESSIBILITY_LABEL",
            comment: "Accessibility label for the 'pen' dialog.",
        )
        return penToolButton
    }

    var buttonCropTool: UIButton {
        let cropButton = mediaToolbar.cropToolButton
        cropButton.accessibilityLabel = OWSLocalizedString(
            "ATTACHMENT_TOOL_BUTTON_CROP_SCALE_ACCESSIBILITY_LABEL",
            comment: "Accessibility label for the 'crop/scale image' dialog.",
        )
        return cropButton
    }

    var buttonMediaQuality: UIButton {
        let mediaQualityButton = mediaToolbar.mediaQualityButton
        mediaQualityButton.accessibilityLabel = OWSLocalizedString(
            "ATTACHMENT_TOOL_BUTTON_MEDIA_QUALITY_ACCESSIBILITY_LABEL",
            comment: "Accessibility label for the 'high/standard quality' dialog.",
        )
        return mediaQualityButton
    }

    var buttonSaveMedia: UIButton {
        mediaToolbar.saveMediaButton
    }

    var buttonAddMedia: UIButton {
        let mediaQualityButton = mediaToolbar.addMediaButton
        mediaQualityButton.accessibilityLabel = OWSLocalizedString(
            "ATTACHMENT_TOOL_BUTTON_ADD_MEDIA_ACCESSIBILITY_LABEL",
            comment: "Accessibility label for the 'add media' dialog.",
        )
        return mediaQualityButton
    }
}

private class MediaToolbar: UIView {

    struct AvailableButtons: OptionSet {
        let rawValue: Int

        static let pen = AvailableButtons(rawValue: 1 << 0)
        static let crop = AvailableButtons(rawValue: 1 << 1)
        static let mediaQuality = AvailableButtons(rawValue: 1 << 2)
        static let save = AvailableButtons(rawValue: 1 << 3)
        static let addMedia = AvailableButtons(rawValue: 1 << 4)

        static let all: AvailableButtons = [.pen, .crop, .mediaQuality, .save, .addMedia]
    }

    func set(availableButtons: AvailableButtons, animated: Bool) {
        penToolButton.setIsHidden(!availableButtons.contains(.pen), animated: animated)
        cropToolButton.setIsHidden(!availableButtons.contains(.crop), animated: animated)
        mediaQualityButton.setIsHidden(!availableButtons.contains(.mediaQuality), animated: animated)
        saveMediaButton.setIsHidden(!availableButtons.contains(.save), animated: animated)
        addMediaButton.setIsHidden(!availableButtons.contains(.addMedia), animated: animated)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        directionalLayoutMargins = .init(hMargin: 0, vMargin: 8)
        if #unavailable(iOS 26) {
            // More space between buttons and the top edge of the blurred background.
            directionalLayoutMargins.top = 16
        }

        let stackView = UIStackView(arrangedSubviews: [
            cropToolButton,
            penToolButton,
            mediaQualityButton,
            saveMediaButton,
            addMediaButton,
        ])
        if #available(iOS 26, *) {
            stackView.spacing = 10
            stackView.directionalLayoutMargins = .init(hMargin: 2, vMargin: 0)
            stackView.isLayoutMarginsRelativeArrangement = true
            stackView.translatesAutoresizingMaskIntoConstraints = false

            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = true
            let glassEffectView = UIVisualEffectView(effect: glassEffect)
            glassEffectView.cornerConfiguration = .capsule()
            glassEffectView.clipsToBounds = true
            glassEffectView.translatesAutoresizingMaskIntoConstraints = false
            glassEffectView.contentView.addSubview(stackView)
            addSubview(glassEffectView)
            NSLayoutConstraint.activate([
                // Glass panel wraps around the stack view and is centered horizontally.
                glassEffectView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
                glassEffectView.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
                glassEffectView.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
                glassEffectView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),

                stackView.topAnchor.constraint(equalTo: glassEffectView.topAnchor),
                stackView.leadingAnchor.constraint(equalTo: glassEffectView.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: glassEffectView.trailingAnchor),
                stackView.bottomAnchor.constraint(equalTo: glassEffectView.bottomAnchor),
            ])
        } else {
            stackView.spacing = 16
            stackView.translatesAutoresizingMaskIntoConstraints = false

            // Stack view has leading edge alignment.
            addSubview(stackView)
            NSLayoutConstraint.activate([
                stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
                stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
                stackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            ])
        }

        stackView.arrangedSubviews.compactMap { $0 as? UIButton }.forEach { button in
            button.setCompressionResistanceHigh()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    private static func buttonConfiguration(image: UIImage) -> UIButton.Configuration {
        var configuration: UIButton.Configuration
        if #available(iOS 26, *) {
            configuration = .plain()
        } else {
            configuration = .bordered()
            configuration.cornerStyle = .capsule
            configuration.baseBackgroundColor = .Signal.primaryFill
        }
        configuration.image = image
        configuration.contentInsets = .init(margin: 10) // 44 dp buttons given 24 dp images
        return configuration
    }

    lazy var penToolButton = UIButton(configuration: Self.buttonConfiguration(
        image: UIImage(imageLiteralResourceName: "brush-pen"),
    ))
    lazy var cropToolButton = UIButton(configuration: Self.buttonConfiguration(
        image: UIImage(imageLiteralResourceName: "crop-rotate"),
    ))
    lazy var mediaQualityButton = UIButton(configuration: Self.buttonConfiguration(
        image: MediaToolbar.iconMediaQualityStandard,
    ))
    lazy var saveMediaButton = UIButton(configuration: Self.buttonConfiguration(
        image: UIImage(imageLiteralResourceName: "save"),
    ))
    lazy var addMediaButton = UIButton(configuration: Self.buttonConfiguration(
        image: UIImage(imageLiteralResourceName: "photo-plus"),
    ))

    private static let iconMediaQualityHigh = UIImage(imageLiteralResourceName: "hd")
    private static let iconMediaQualityStandard = UIImage(imageLiteralResourceName: "hd-slash")

    fileprivate func setIsMediaQualityHigh(enabled: Bool, animated: Bool) {
        let image = enabled ? MediaToolbar.iconMediaQualityHigh : MediaToolbar.iconMediaQualityStandard
        mediaQualityButton.setImage(image, animated: animated)
    }
}

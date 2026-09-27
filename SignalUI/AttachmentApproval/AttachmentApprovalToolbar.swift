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

    private var contentLayoutGuideLeading: NSLayoutConstraint?
    private var contentLayoutGuideTrailing: NSLayoutConstraint?
    private var contentLayoutGuideBottom: NSLayoutConstraint?
    private var contentLayoutGuideWithKeyboard: NSLayoutConstraint?

    @available(iOS, deprecated: 26)
    private var blurBackgroundTopInEditingMode: NSLayoutConstraint?

    /**
     View is designed to be pinned to the bottom of the screen. Whenever keyboard appears the VC should
     assign an appropriate value to this property, possible within an animation block.
     */
    private var _keyboardHeight: CGFloat = 0

    var keyboardHeight: CGFloat {
        get { _keyboardHeight }
        set { setKeyboardHeight(newValue, animated: false) }
    }

    func setKeyboardHeight(_ keyboardHeight: CGFloat, animated: Bool) {
        guard animated else {
            setKeyboardHeight(keyboardHeight)
            return
        }

        let animator = Self.defaultAnimator()
        setKeyboardHeight(keyboardHeight, using: animator)
        animator.startAnimation()
    }

    func setKeyboardHeight(_ keyboardHeight: CGFloat, using animator: UIViewPropertyAnimator? = nil) {
        _keyboardHeight = keyboardHeight
        updateContentLayoutGuideConstraints()
        updateContents(using: animator)
    }

    weak var captionToolbarDelegate: MediaCaptionToolbarDelegate?

    // Top row: previews of media items. Only shown when there are multiple.
    lazy var galleryRailView: GalleryRailView = {
        let galleryRailView = GalleryRailView()
        galleryRailView.itemSize = 44
        if #unavailable(iOS 26) {
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
        )
        toolbar.delegate = self
        if #unavailable(iOS 26) {
            // We want top margin at only 8 dp (it comes from AttachmentApprovalToolbar)
            // when keyboard is up and this MediaCaptionToolbar is the only visible control.
            toolbar.directionalLayoutMargins.top = 0
        }
        return toolbar
    }()

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [galleryRailView, mediaToolbar, mediaCaptionToolbar])
        stackView.axis = .vertical
        // Both `mediaToolbar` and `mediaCaptionToolbar` have 8 dp of vertical margins in them.
        // iOS 26 needs more space - 24dp - between rows.
        if #available(iOS 26, *) {
            stackView.spacing = 8
        } else {
            // Compensate for lack of top margin in `mediaCaptionToolbar`.
            stackView.setCustomSpacing(MediaCaptionToolbar.verticalPadding, after: mediaToolbar)
        }
        return stackView
    }()

    private func updateContentLayoutGuideConstraints() {
        // `contentLayoutGuideBottom` is always active, but has lower priotiry than
        // `contentLayoutGuideWithKeyboard` which is only active when on-screen keyboard is up.
        guard let contentLayoutGuideBottom, let contentLayoutGuideWithKeyboard else { return }

        guard keyboardHeight == 0 else {
            // MediaCaptionToolbar has a bottom margin that will give us correct vertical spacing to the keyboard.
            contentLayoutGuideWithKeyboard.constant = keyboardHeight
            contentLayoutGuideWithKeyboard.isActive = true
            return
        }

        contentLayoutGuideWithKeyboard.isActive = false

        let bottomInset: CGFloat
        if #available(iOS 26, *) {
            // Media caption text field has a glass background. Ensure proper padding around that.

            if safeAreaInsets.bottom > 0 {
                // On devices without a home button we want 28 dp padding around
                // left, right and bottom edges of text field's glass pill.
                let horizontalInset: CGFloat = 28
                contentLayoutGuideLeading?.constant = horizontalInset
                contentLayoutGuideTrailing?.constant = -horizontalInset

                // MediaCaptionToolbar has an extra 8 dp bottom margin that needs to be subtracted
                // to get proper spacing to glass pill.
                bottomInset = horizontalInset - MediaCaptionToolbar.verticalPadding
            } else {
                // 24 dp spacing between glass pill's bottom edge and screen's bottom edge.
                // Side margins remain standard.
                bottomInset = 24
            }
        } else {
            // Pre-iOS 26 devices.
            // Simply pin to the screen's safe area's bottom edge.
            // Horizontal margins remain standard.
            bottomInset = safeAreaInsets.bottom
        }
        contentLayoutGuideBottom.constant = bottomInset
    }

    private var currentAttachmentItem: AttachmentApprovalItem?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        tintColor = .Signal.label

        let leading: NSLayoutConstraint
        let trailing: NSLayoutConstraint
        if #available(iOS 26, *) {
            // We need adjustable horizontal margins on some iOS 26 devices.
            // Therefore, constrain to safe area edges and don't use layoutMargins at all.
            let defaultMargin = OWSTableViewController2.defaultHOuterMargin
            leading = contentLayoutGuide.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: defaultMargin,
            )
            trailing = contentLayoutGuide.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -defaultMargin,
            )

            contentLayoutGuideLeading = leading
            contentLayoutGuideTrailing = trailing
        } else {
            preservesSuperviewLayoutMargins = true
            leading = contentLayoutGuide.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor)
            trailing = contentLayoutGuide.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
        }

        contentLayoutGuideBottom = bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor)
        contentLayoutGuideBottom?.priority = .required - 10

        // Higher priority than `contentLayoutGuideBottom` but only active when keyboard is up.
        contentLayoutGuideWithKeyboard = bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor)

        // View controller will use this layout guide to position UI elements above the keyboard.
        contentLayoutGuide.identifier = "AttachmentApprovalToolbar.contentLayoutGuide"
        addLayoutGuide(contentLayoutGuide)
        NSLayoutConstraint.activate([
            contentLayoutGuide.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            leading,
            trailing,
            contentLayoutGuideBottom!,
        ])

        // Pre-iOS 26 has blur background underneath caption input field and buttons.
        stackView.translatesAutoresizingMaskIntoConstraints = false
        if #unavailable(iOS 26) {
            let blurBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
            blurBackgroundView.translatesAutoresizingMaskIntoConstraints = false
            blurBackgroundView.contentView.addSubview(stackView)
            addSubview(blurBackgroundView)

            // This will pull down the background to be aligned with the caption input field.
            blurBackgroundTopInEditingMode = blurBackgroundView.topAnchor.constraint(
                equalTo: mediaCaptionToolbar.topAnchor,
                constant: -8,
            )
            // Priority lower than `blurBackgroundTopInEditingMode`.
            let blurBackgroundTopPermanent = blurBackgroundView.topAnchor.constraint(equalTo: topAnchor)
            blurBackgroundTopPermanent.priority = .required - 10
            NSLayoutConstraint.activate([
                blurBackgroundTopPermanent,
                blurBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
                blurBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
                blurBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

        } else {
            addSubview(stackView)
        }
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
        ])
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()

        updateContentLayoutGuideConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var supplementaryViewContainer: UIView?

    private func set(supplementaryView: UIView?) {
        if
            let supplementaryView,
            let existingView = supplementaryViewContainer?.subviews.first,
            existingView === supplementaryView
        {
            Logger.debug("SKIPPING SUPPLEMENTARY VIEW UPDATE")
            return
        }

        if let supplementaryViewContainer {
            stackView.removeArrangedSubview(supplementaryViewContainer)
            supplementaryViewContainer.removeFromSuperview()
            self.supplementaryViewContainer = nil
        }
        guard let supplementaryView else {
            return
        }

        let containerView = UIView()
        containerView.directionalLayoutMargins = .init(hMargin: 0, vMargin: 8)
        supplementaryView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(supplementaryView)
        NSLayoutConstraint.activate([
            supplementaryView.topAnchor.constraint(equalTo: containerView.layoutMarginsGuide.topAnchor),
            supplementaryView.leadingAnchor.constraint(equalTo: containerView.layoutMarginsGuide.leadingAnchor),
            supplementaryView.trailingAnchor.constraint(equalTo: containerView.layoutMarginsGuide.trailingAnchor),
            supplementaryView.bottomAnchor.constraint(equalTo: containerView.layoutMarginsGuide.bottomAnchor),
        ])
        stackView.insertArrangedSubview(containerView, at: 0)
        self.supplementaryViewContainer = containerView
    }

    class func defaultAnimator() -> UIViewPropertyAnimator {
        UIViewPropertyAnimator(duration: 0.15, springDamping: 1, springResponse: 0.15)
    }

    var currentHeight: CGFloat {
        guard let contentLayoutGuideBottom else { return frame.height }

        // Always return toolbar height as if keyboard wasn't up.
        return contentLayoutGuide.layoutFrame.minY + stackView.frame.height + contentLayoutGuideBottom.constant
    }

    private func updateContents(using animator: UIViewPropertyAnimator? = nil) {
        // When on-screen keyboard is up we make everything except for `mediaCaptionToolbar` invisible.
        // But we do so adjusting `alpha` and not `isHidden` to preserve dimensions of the `AttachmentApprovalToolbar`
        // and with it - content insets in the media preview view.
        let nonCaptionFieldElementAlpha: CGFloat = mediaCaptionToolbar.isEditingText ? 0 : 1

        // On iOS 15-18 pull down background to align with the top of the caption input field.
        blurBackgroundTopInEditingMode?.isActive = mediaCaptionToolbar.isEditingText

        // Show/hide Gallery Rail.
        let hideMediaStrip = configuration.isMediaStripVisible == false
        galleryRailView.setIsHidden(hideMediaStrip, using: animator)
        if hideMediaStrip == false {
            if let animator {
                animator.addAnimations {
                    self.galleryRailView.alpha = nonCaptionFieldElementAlpha
                }
            } else {
                galleryRailView.alpha = nonCaptionFieldElementAlpha
            }
        }

        // Video timeline view is also hidden when editing caption.
        if let supplementaryViewContainer {
            if let animator {
                animator.addAnimations {
                    supplementaryViewContainer.alpha = nonCaptionFieldElementAlpha
                }
            } else {
                supplementaryViewContainer.alpha = nonCaptionFieldElementAlpha
            }
        }

        // Update controls in media toolbar.
        mediaToolbar.setIsMediaQualityHigh(
            enabled: configuration.isMediaHighQualityEnabled,
            using: animator,
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
        mediaToolbar.set(availableButtons: availableButtons, using: animator)
        let hideMediaToolbar = availableButtons.isEmpty
        mediaToolbar.setIsHidden(availableButtons.isEmpty, using: animator)
        if hideMediaToolbar == false {
            if let animator {
                animator.addAnimations {
                    self.mediaToolbar.alpha = nonCaptionFieldElementAlpha
                }
            } else {
                mediaToolbar.alpha = nonCaptionFieldElementAlpha
            }
        }

        // Update caption input field.
        mediaCaptionToolbar.setProceedButtonImage(
            UIImage(imageLiteralResourceName: configuration.proceedButtonIcon.rawValue),
        )
        mediaCaptionToolbar.setIsViewOnce(
            enabled: configuration.canToggleViewOnce,
            on: configuration.isViewOnceOn,
            using: animator,
        )

        showViewOnceTooltipIfNecessary()
    }

    func update(
        using attachmentItem: AttachmentApprovalItem,
        configuration: Configuration,
        supplementaryToolbarView: UIView?,
        animator: UIViewPropertyAnimator?,
    ) {
        // De-bounce
        if attachmentItem.isIdenticalTo(currentAttachmentItem as AttachmentApprovalItem?), self.configuration == configuration {
            return
        }

        self.currentAttachmentItem = attachmentItem
        self.configuration = configuration

        guard let animator else {
            set(supplementaryView: supplementaryToolbarView)
            updateContents()
            return
        }

        animator.addAnimations {
            self.set(supplementaryView: supplementaryToolbarView)
        }
        updateContents(using: animator)
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
        captionToolbarDelegate?.mediaCaptionToolbarDidBeginEditing(mediaCaptionToolbar)
    }

    func mediaCaptionToolbarDidEndEditing(_ mediaCaptionToolbar: MediaCaptionToolbar) {
        captionToolbarDelegate?.mediaCaptionToolbarDidEndEditing(mediaCaptionToolbar)
    }

    func mediaCaptionToolbarDidChangeText(_ mediaCaptionToolbar: MediaCaptionToolbar) {
        captionToolbarDelegate?.mediaCaptionToolbarDidChangeText(mediaCaptionToolbar)
    }

    func mediaCaptionToolBarDidChangeHeight(_ mediaCaptionToolbar: MediaCaptionToolbar) {
        setNeedsLayout()
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

        DispatchQueue.global().async { [self] in
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

    func set(availableButtons: AvailableButtons, using animator: UIViewPropertyAnimator? = nil) {
        penToolButton.setIsHidden(!availableButtons.contains(.pen), using: animator)
        cropToolButton.setIsHidden(!availableButtons.contains(.crop), using: animator)
        mediaQualityButton.setIsHidden(!availableButtons.contains(.mediaQuality), using: animator)
        saveMediaButton.setIsHidden(!availableButtons.contains(.save), using: animator)
        addMediaButton.setIsHidden(!availableButtons.contains(.addMedia), using: animator)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        directionalLayoutMargins = .init(hMargin: 0, vMargin: 8)

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
        image: UIImage(imageLiteralResourceName: "album-plus"),
    ))

    private static let iconMediaQualityHigh = UIImage(imageLiteralResourceName: "hd")
    private static let iconMediaQualityStandard = UIImage(imageLiteralResourceName: "hd-slash")

    fileprivate func setIsMediaQualityHigh(enabled: Bool, using animator: UIViewPropertyAnimator? = nil) {
        let image = enabled ? MediaToolbar.iconMediaQualityHigh : MediaToolbar.iconMediaQualityStandard

        guard let animator else {
            mediaQualityButton.configuration?.image = image
            return
        }

        animator.addAnimations {
            self.mediaQualityButton.configuration?.image = image
        }
    }
}

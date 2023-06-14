//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalServiceKit

/// This class exists to be a drop-in replacement for the Context-menu related APIs available on UIButton
/// in iOS 14 and above.
/// When we drop iOS 13, we can remove this class and replace all usages with a vanilla UIButton.
/// As such, its exposed API should remain identical to what UIButton exposes in iOS 14.
public class ContextMenuButton: UIButton, ContextMenuInteractionDelegate {
    override public var intrinsicContentSize: CGSize { .zero }

    public var contextMenu: ContextMenu? {
        didSet { updateHandlers() }
    }

    /// The preferred position of the context menu, when presented.
    public let preferredContextMenuPosition: ContextMenuPosition?

    /// When defined as `true` the context menu will present immediately on touch down.
    /// Otherwise, the context menu is presented after a long press. If you are trying to handle
    /// another action as a primary action, keep in mind that when the long press is triggered
    /// all other events will be canceled. You can verify the long press has failed by checking
    /// `isShowingContextMenu` is false.
    public var showsContextMenuAsPrimaryAction = false {
        didSet { updateHandlers() }
    }

    public var forceDarkTheme = false

    public init(
        contextMenu: ContextMenu? = nil,
        preferredContextMenuPosition: ContextMenuPosition? = nil
    ) {
        self.contextMenu = contextMenu
        self.preferredContextMenuPosition = preferredContextMenuPosition

        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Note: fake value used just to mimic UIButton iOS 14+ behavior
    private lazy var _contextMenuInteraction = ContextMenuInteraction(delegate: self)

    public var isShowingContextMenu: Bool { contextMenuController != nil }

    private var contextMenuConfiguration: ContextMenuConfiguration?
    private var contextMenuController: ContextMenuController?

    public func showContextMenu(initiatingGestureRecognizer: UIGestureRecognizer? = nil) {
        guard !isShowingContextMenu else { return }
        guard
            let window = window,
            let contextMenuConfiguration = self.contextMenuInteraction(
                _contextMenuInteraction,
                configurationForMenuAtLocation: initiatingGestureRecognizer?.location(in: self) ?? bounds.center
            ),
            let contextMenu = contextMenuConfiguration.actionProvider?([])
        else {
            return
        }

        let menuPosition = menuPosition(window: window)

        guard let preview = contextMenuTargetedPreview(menuPosition: menuPosition) else {
            return
        }

        let menuAccessory = contextMenuActionsAccessory(
            menuPosition: menuPosition,
            menu: contextMenu
        )

        let controller = ContextMenuController(
            configuration: contextMenuConfiguration,
            preview: preview,
            initiatingGestureRecognizer: initiatingGestureRecognizer,
            menuAccessory: menuAccessory,
            presentImmediately: true,
            renderBackgroundBlur: false,
            previewRenderMode: .fade
        )
        contextMenuController = controller
        controller.delegate = self
        self.contextMenuConfiguration = contextMenuConfiguration

        window.addSubview(controller.view)
        controller.view.frame = window.bounds

        self.contextMenuInteraction(_contextMenuInteraction, willDisplayMenuForConfiguration: contextMenuConfiguration)
    }

    public func dismissContextMenu(animated: Bool, completion: (() -> Void)? = nil) {
        func dismiss() {
            contextMenuController?.view?.removeFromSuperview()
            contextMenuController = nil
            completion?()
            if let contextMenuConfiguration = contextMenuConfiguration {
                self.contextMenuInteraction(_contextMenuInteraction, didEndForConfiguration: contextMenuConfiguration)
                self.contextMenuConfiguration = nil
            } else {
                OWSLogger.info("Dismissing context menu with no configuration present")
            }
        }

        if let contextMenuConfiguration = contextMenuConfiguration {
            self.contextMenuInteraction(_contextMenuInteraction, willEndForConfiguration: contextMenuConfiguration)
        } else {
            owsFailDebug("Dismissing context menu with no configuration present")
        }
        if animated {
            contextMenuController?.animateOut(dismiss)
        } else {
            dismiss()
        }
    }

    // MARK: - Taps and gestures

    private lazy var longPressGestureRecognizer: UILongPressGestureRecognizer = {
        let gestureRecognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(longPressRecognized(_:))
        )
        gestureRecognizer.minimumPressDuration = showsContextMenuAsPrimaryAction ? 0 : 0.5
        return gestureRecognizer
    }()

    private func updateHandlers() {
        if contextMenu == nil {
            removeGestureRecognizer(longPressGestureRecognizer)
            return
        }

        addGestureRecognizer(longPressGestureRecognizer)
    }

    @objc
    private func longPressRecognized(_ sender: UILongPressGestureRecognizer) {
        switch sender.state {
        case .began:
            // If there are any other touch events waiting,
            // cancel them. The gesture recognizer wins.
            cancelTracking(with: nil)
            showContextMenu(initiatingGestureRecognizer: sender)
        case .changed:
            contextMenuController?.gestureDidChange()
        case .ended, .cancelled:
            contextMenuController?.gestureDidEnd()
        default:
            break
        }
    }

    // MARK: - 

    /// A representation of the context menu's relative presentation origin
    /// relative to the button's frame in the window.
    public struct ContextMenuPosition {
        public enum VerticalEdge {
            case top
            case bottom

            fileprivate var accessoryAlignment: ContextMenuTargetedPreviewAccessory.AccessoryAlignment.Edge {
                switch self {
                case .top: return .top
                case .bottom: return .bottom
                }
            }
        }

        public enum HorizontalEdge {
            case left
            case right

            var targetedPreviewAlignment: ContextMenuTargetedPreview.Alignment {
                switch self {
                case .left: return .left
                case .right: return .right
                }
            }

            var accessoryAlignment: ContextMenuTargetedPreviewAccessory.AccessoryAlignment.Edge {
                switch self {
                case .left: return .leading
                case .right: return .trailing
                }
            }
        }

        public let verticalPinnedEdge: VerticalEdge
        public let horizontalPinnedEdge: HorizontalEdge
        public let alignmentOffset: CGPoint

        /// Construct a context menu position with origin at the given edges,
        /// adjusted by the given offset.
        /// - SeeAlso
        /// ``ContextMenuTargetedPreviewAccessory.AccessoryAlignment.alignmentOffset``
        public init(
            verticalPinnedEdge: VerticalEdge,
            horizontalPinnedEdge: HorizontalEdge,
            alignmentOffset: CGPoint
        ) {
            self.verticalPinnedEdge = verticalPinnedEdge
            self.horizontalPinnedEdge = horizontalPinnedEdge
            self.alignmentOffset = alignmentOffset
        }

        fileprivate init(
            rect: CGRect,
            locationInRect: CGRect,
            alignmentOffset: CGPoint
        ) {
            let isCloserToTheBottom = (rect.maxY - locationInRect.maxY) <= locationInRect.minY
            let isCloserToTheRight = (rect.maxX - locationInRect.maxX) <= locationInRect.minX

            let verticalPinnedEdge: VerticalEdge = isCloserToTheBottom ? .top : .bottom
            let horizontalPinnedEdge: HorizontalEdge = isCloserToTheRight ? .right : .left

            self.init(
                verticalPinnedEdge: verticalPinnedEdge,
                horizontalPinnedEdge: horizontalPinnedEdge,
                alignmentOffset: alignmentOffset
            )
        }
    }

    private func menuPosition(window: UIWindow) -> ContextMenuPosition {
        if let preferredContextMenuPosition {
            return preferredContextMenuPosition
        }

        return ContextMenuPosition(
            rect: window.bounds,
            locationInRect: window.convert(frame, from: superview),
            alignmentOffset: CGPoint(x: 8, y: 16)
        )
    }

    private func contextMenuTargetedPreview(menuPosition: ContextMenuPosition) -> ContextMenuTargetedPreview? {
        ContextMenuTargetedPreview(
            view: self,
            alignment: menuPosition.horizontalPinnedEdge.targetedPreviewAlignment,
            accessoryViews: nil
        )
    }

    private func contextMenuActionsAccessory(menuPosition: ContextMenuPosition, menu: ContextMenu) -> ContextMenuActionsAccessory {
        let accessory = ContextMenuActionsAccessory(
            menu: menu,
            accessoryAlignment: ContextMenuActionsAccessory.AccessoryAlignment(
                alignments: [
                    (menuPosition.verticalPinnedEdge.accessoryAlignment, .exterior),
                    (menuPosition.horizontalPinnedEdge.accessoryAlignment, .interior)
                ],
                alignmentOffset: menuPosition.alignmentOffset
            ),
            forceDarkTheme: forceDarkTheme
        )
        accessory.delegate = self
        return accessory
    }

    /// Note: If you override this method on UIButton on iOS 14 or later, whatever is returned is used for the
    /// context menu that is ultimately displayed.
    /// This class is meant to be a perfect replacement for UIButton to get context menu functionality prior to
    /// iOS 14, so we mimic that behavior and use this method as the source of truth, allowing it to be overridden.
    public func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> ContextMenuConfiguration? {
        return self.contextMenu.map { contextMenu in
            return .init(identifier: nil, forceDarkTheme: forceDarkTheme, actionProvider: { _ in
                return contextMenu
            })
        }
    }

    public func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: ContextMenuConfiguration
    ) -> ContextMenuTargetedPreview? {
        return nil
    }

    public func contextMenuInteraction(_ interaction: ContextMenuInteraction, willDisplayMenuForConfiguration: ContextMenuConfiguration) {
        // Do nothing
    }

    public func contextMenuInteraction(_ interaction: ContextMenuInteraction, willEndForConfiguration: ContextMenuConfiguration) {
        // Do nothing
    }

    public func contextMenuInteraction(_ interaction: ContextMenuInteraction, didEndForConfiguration: ContextMenuConfiguration) {
        // Do nothing
    }
}

extension ContextMenuButton: ContextMenuControllerDelegate {
    func contextMenuControllerRequestsDismissal(_ contextMenuController: ContextMenuController) {
        dismissContextMenu(animated: true)
    }
}

extension ContextMenuButton: ContextMenuTargetedPreviewAccessoryInteractionDelegate {
    func contextMenuTargetedPreviewAccessoryPreviewAlignment(_ accessory: ContextMenuTargetedPreviewAccessory) -> ContextMenuTargetedPreview.Alignment {
        contextMenuController?.contextMenuPreview.alignment ?? .center
    }

    func contextMenuTargetedPreviewAccessoryRequestsDismissal(_ accessory: ContextMenuTargetedPreviewAccessory, completion: @escaping () -> Void) {
        dismissContextMenu(animated: true, completion: completion)
    }

    func contextMenuTargetedPreviewAccessoryRequestsEmojiPicker(
        for message: TSMessage,
        accessory: ContextMenuTargetedPreviewAccessory,
        completion: @escaping (String) -> Void
    ) {
        owsFailDebug("Emoji picker not supported from ContextMenuButton")
    }
}

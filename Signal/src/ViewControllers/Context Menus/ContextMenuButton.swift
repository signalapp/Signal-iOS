//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalCoreKit

public class ContextMenuButton: UIButton {
    public var contextMenu: ContextMenu? {
        didSet { updateHandlers() }
    }
    /// When defined as `true` the context menu will present immediately on touch down.
    /// Otherwise, the context menu is presented after a long press. If you are trying to handle
    /// another action as a primary action, keep in mind that when the long press is triggered
    /// all other events will be canceled. You can verify the long press has failed by checking
    /// `isShowingContextMenu` is false.
    public var showsContextMenuAsPrimaryAction = false {
        didSet { updateHandlers() }
    }
    public var forceDarkTheme = false

    public init(contextMenu: ContextMenu? = nil) {
        self.contextMenu = contextMenu
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var isShowingContextMenu: Bool { contextMenuController != nil }

    private var contextMenuController: ContextMenuController?
    public func showContextMenu(initiatingGestureRecognizer: UIGestureRecognizer? = nil) {
        guard !isShowingContextMenu else { return }
        guard let window = window, let contextMenu = contextMenu else { return }

        let menuPosition = ContextMenuPosition(
            rect: window.bounds,
            locationInRect: window.convert(frame, from: superview)
        )

        guard let preview = contextMenuTargetedPreview(menuPosition: menuPosition) else { return }

        let configuration = ContextMenuConfiguration(
            identifier: NSUUID(),
            forceDarkTheme: forceDarkTheme,
            actionProvider: { _ in contextMenu }
        )

        let menuAccessory = contextMenuActionsAccessory(
            menuPosition: menuPosition,
            menu: contextMenu
        )

        let controller = ContextMenuController(
            configuration: configuration,
            preview: preview,
            initiatingGestureRecognizer: initiatingGestureRecognizer,
            menuAccessory: menuAccessory,
            presentImmediately: true,
            renderBackgroundBlur: false,
            previewRenderMode: .fade
        )
        contextMenuController = controller
        controller.delegate = self

        ImpactHapticFeedback.impactOccured(style: .medium, intensity: 0.8)

        window.addSubview(controller.view)
        controller.view.frame = window.bounds
    }

    public func dismissContextMenu(animated: Bool, completion: (() -> Void)? = nil) {
        func dismiss() {
            contextMenuController?.view?.removeFromSuperview()
            contextMenuController = nil
            completion?()
        }

        if animated {
            contextMenuController?.animateOut(dismiss)
        } else {
            dismiss()
        }
    }

    private lazy var longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressRecognized(_:)))
    private func updateHandlers() {
        if contextMenu == nil {
            removeGestureRecognizer(longPressGestureRecognizer)
        } else {
            addGestureRecognizer(longPressGestureRecognizer)
        }

        longPressGestureRecognizer.minimumPressDuration = showsContextMenuAsPrimaryAction ? 0 : 0.5
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

    /// A RTL agnostic representation of the context menus relative presentation origin
    /// within the viewport. In general, buttons on the right of the screen will present a
    /// menu on the right of the screen, buttons on the left of the screen will present a
    /// menu on the left, etc.
    private struct ContextMenuPosition {
        enum VerticalEdge {
            case top
            case bottom

            var accessoryAlignment: ContextMenuTargetedPreviewAccessory.AccessoryAlignment.Edge {
                switch self {
                case .top: return .top
                case .bottom: return .bottom
                }
            }
        }

        enum HorizontalEdge {
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
                case .left: return CurrentAppContext().isRTL ? .trailing : .leading
                case .right: return CurrentAppContext().isRTL ? .leading : .trailing
                }
            }
        }

        let verticalPinnedEdge: VerticalEdge
        let horizontalPinnedEdge: HorizontalEdge

        var alignmentOffset: CGPoint {
            switch verticalPinnedEdge {
            case .top:
                return CGPoint(x: 0, y: -16)
            case .bottom:
                return CGPoint(x: 0, y: 16)
            }
        }

        init(rect: CGRect, locationInRect: CGRect) {
            let isCloserToTheBottom = (rect.maxY - locationInRect.maxY) <= locationInRect.minY
            let isCloserToTheRight = (rect.maxX - locationInRect.maxX) <= locationInRect.minX

            verticalPinnedEdge = isCloserToTheBottom ? .top : .bottom
            horizontalPinnedEdge = isCloserToTheRight ? .right : .left
        }
    }

    private func contextMenuTargetedPreview(menuPosition: ContextMenuPosition) -> ContextMenuTargetedPreview? {
        .init(view: self, alignment: menuPosition.horizontalPinnedEdge.targetedPreviewAlignment, accessoryViews: nil)
    }

    private func contextMenuActionsAccessory(menuPosition: ContextMenuPosition, menu: ContextMenu) -> ContextMenuActionsAccessory {
        let accessory = ContextMenuActionsAccessory(
            menu: menu,
            accessoryAlignment: .init(
                alignments: [(menuPosition.verticalPinnedEdge.accessoryAlignment, .exterior), (menuPosition.horizontalPinnedEdge.accessoryAlignment, .interior)],
                alignmentOffset: menuPosition.alignmentOffset
            ),
            forceDarkTheme: forceDarkTheme
        )
        accessory.delegate = self
        return accessory
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

    func contextMenuTargetedPreviewAccessoryRequestsEmojiPicker(_ accessory: ContextMenuTargetedPreviewAccessory, completion: @escaping (String) -> Void) {
        owsFailDebug("Emoji picker not supported from ContextMenuButton")
    }
}

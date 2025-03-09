//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
public import UIKit

public class MessageAction: NSObject {

    let block: (_ sender: Any?) -> Void
    let accessibilityIdentifier: String
    let contextMenuTitle: String
    let contextMenuAttributes: ContextMenuAction.Attributes

    public enum MessageActionType {
        case reply
        case copy
        case info
        case delete
        case share
        case forward
        case select
        case speak
        case stopSpeaking
        case edit
        case showPaymentDetails
        case showStickerPack
    }

    let actionType: MessageActionType

    public init(_ actionType: MessageActionType,
                accessibilityLabel: String,
                accessibilityIdentifier: String,
                contextMenuTitle: String,
                contextMenuAttributes: ContextMenuAction.Attributes,
                block: @escaping (_ sender: Any?) -> Void) {
        self.actionType = actionType
        self.accessibilityIdentifier = accessibilityIdentifier
        self.contextMenuTitle = contextMenuTitle
        self.contextMenuAttributes = contextMenuAttributes
        self.block = block
        super.init()
        self.accessibilityLabel = accessibilityLabel
    }

    var contextMenuIcon: UIImage {
        let icon: ThemeIcon = {
            switch actionType {
            case .reply:
                return .contextMenuReply
            case .copy:
                return .contextMenuCopy
            case .info:
                return .contextMenuInfo
            case .delete:
                return .contextMenuDelete
            case .share:
                return .contextMenuShare
            case .forward:
                return .contextMenuForward
            case .select:
                return .contextMenuSelect
            case .speak:
                return .contextMenuSpeak
            case .stopSpeaking:
                return .contextMenuStopSpeaking
            case .edit:
                return .contextMenuEdit
            case .showPaymentDetails:
                return .settingsPayments
            case .showStickerPack:
                return .contextMenuSticker
            }
        }()
        return Theme.iconImage(icon)
    }

    var barButtonImage: UIImage {
        let icon: ThemeIcon = {
            switch actionType {
            case .delete:
                return .buttonDelete
            case .forward:
                return .buttonForward
            default:
                owsFail("Invalid icon")
            }
        }()
        return Theme.iconImage(icon)
    }
}

public protocol MessageActionsToolbarDelegate: AnyObject {
    func messageActionsToolbar(_ messageActionsToolbar: MessageActionsToolbar, executedAction: MessageAction)
    var messageActionsToolbarSelectedInteractionCount: Int { get }
}

public class MessageActionsToolbar: UIToolbar {

    weak var actionDelegate: MessageActionsToolbarDelegate?

    enum Mode {
        case normal(messagesActions: [MessageAction])
        case selection(deleteMessagesAction: MessageAction,
                       forwardMessagesAction: MessageAction)
    }
    private let mode: Mode

    init(mode: Mode) {
        self.mode = mode

        super.init(frame: .zero)

        isTranslucent = false
        isOpaque = true

        autoresizingMask = .flexibleHeight
        translatesAutoresizingMaskIntoConstraints = false
        setShadowImage(UIImage(), forToolbarPosition: .any)

        buildItems()

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
        applyTheme()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    @objc
    private func applyTheme() {
        AssertIsOnMainThread()

        barTintColor = Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_white

        buildItems()
    }

    public func updateContent() {
        buildItems()
    }

    private func buildItems() {
        switch mode {
        case .normal(let messagesActions):
            buildNormalItems(messagesActions: messagesActions)
        case .selection(let deleteMessagesAction, let forwardMessagesAction):
            buildSelectionItems(deleteMessagesAction: deleteMessagesAction,
                                forwardMessagesAction: forwardMessagesAction)
        }
    }

    var actionItems = [MessageActionsToolbarButton]()

    private func buildNormalItems(messagesActions: [MessageAction]) {
        var newItems = [UIBarButtonItem]()

        var actionItems = [MessageActionsToolbarButton]()
        for action in messagesActions {
            if !newItems.isEmpty {
                newItems.append(.flexibleSpace())
            }

            let actionItem = MessageActionsToolbarButton(actionsToolbar: self, messageAction: action)
            actionItem.tintColor = Theme.primaryIconColor
            actionItem.accessibilityLabel = action.accessibilityLabel
            newItems.append(actionItem)
            actionItems.append(actionItem)
        }

        // If we only have a single button, center it.
        if newItems.count == 1 {
            newItems.insert(.flexibleSpace(), at: 0)
            newItems.append(.flexibleSpace())
        }

        items = newItems
        self.actionItems = actionItems
    }

    private func buildSelectionItems(deleteMessagesAction: MessageAction,
                                     forwardMessagesAction: MessageAction) {

        let deleteItem = MessageActionsToolbarButton(actionsToolbar: self, messageAction: deleteMessagesAction)
        let forwardItem = MessageActionsToolbarButton(actionsToolbar: self, messageAction: forwardMessagesAction)

        let selectedCount: Int = actionDelegate?.messageActionsToolbarSelectedInteractionCount ?? 0
        let labelFormat = OWSLocalizedString("MESSAGE_ACTIONS_TOOLBAR_CAPTION_%d", tableName: "PluralAware",
                                            comment: "Label for the toolbar used in the multi-select mode. The number of selected items (1 or more) is passed.")
        let labelTitle = String.localizedStringWithFormat(labelFormat, selectedCount)
        let label = UILabel()
        label.text = labelTitle
        label.font = UIFont.dynamicTypeBodyClamped
        label.textColor = Theme.primaryTextColor
        label.sizeToFit()
        let labelItem = UIBarButtonItem(customView: label)

        var newItems = [UIBarButtonItem]()
        newItems.append(deleteItem)
        newItems.append(.flexibleSpace())
        newItems.append(labelItem)
        newItems.append(.flexibleSpace())
        newItems.append(forwardItem)

        items = newItems
        self.actionItems = [ deleteItem, forwardItem ]
    }

    public func buttonItem(for actionType: MessageAction.MessageActionType) -> UIBarButtonItem? {
        for actionItem in actionItems {
            if let messageAction = actionItem.messageAction,
               messageAction.actionType == actionType {
                return actionItem
            }
        }
        owsFailDebug("Missing action item: \(actionType).")
        return nil
    }
}

// MARK: -

class MessageActionsToolbarButton: UIBarButtonItem {
    private weak var actionsToolbar: MessageActionsToolbar?
    fileprivate var messageAction: MessageAction?

    init(actionsToolbar: MessageActionsToolbar, messageAction: MessageAction) {
        self.actionsToolbar = actionsToolbar
        self.messageAction = messageAction

        super.init()

        self.image = messageAction.barButtonImage
        self.style = .plain
        self.target = self
        self.action = #selector(didTapItem(_:))
        self.tintColor = Theme.primaryIconColor
        self.accessibilityLabel = messageAction.accessibilityLabel
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func didTapItem(_ item: UIBarButtonItem) {
        AssertIsOnMainThread()

        guard let messageAction = messageAction,
              let actionsToolbar = actionsToolbar,
              let actionDelegate = actionsToolbar.actionDelegate else {
            return
        }
        actionDelegate.messageActionsToolbar(actionsToolbar, executedAction: messageAction)
    }
}

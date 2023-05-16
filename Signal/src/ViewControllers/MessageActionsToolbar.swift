//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

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

    var image: UIImage {
        switch actionType {
        case .reply:
            return Theme.iconImage(.messageActionReply)
        case .copy:
            return Theme.iconImage(.messageActionCopy)
        case .info:
            return Theme.iconImage(.contextMenuInfo24)
        case .delete:
            return Theme.iconImage(.messageActionDelete)
        case .share:
            return Theme.iconImage(.messageActionShare24)
        case .forward:
            return Theme.iconImage(.messageActionForward24)
        case .select:
            return Theme.iconImage(.contextMenuSelect)
        case .speak:
            return Theme.iconImage(.messageActionSpeak)
        case .stopSpeaking:
            return Theme.iconImage(.messageActionStopSpeaking)
        }
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

    deinit {
        Logger.verbose("")
    }

    required init(mode: Mode) {
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
                newItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
            }

            let actionItem = MessageActionsToolbarButton(actionsToolbar: self, messageAction: action)
            actionItem.tintColor = Theme.primaryIconColor
            actionItem.accessibilityLabel = action.accessibilityLabel
            newItems.append(actionItem)
            actionItems.append(actionItem)
        }

        // If we only have a single button, center it.
        if newItems.count == 1 {
            newItems.insert(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), at: 0)
            newItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
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
        newItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        newItems.append(labelItem)
        newItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
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

    required override init() {
        super.init()
    }

    required init(actionsToolbar: MessageActionsToolbar, messageAction: MessageAction) {
        self.actionsToolbar = actionsToolbar
        self.messageAction = messageAction

        super.init()

        self.image = messageAction.image.withRenderingMode(.alwaysTemplate)
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

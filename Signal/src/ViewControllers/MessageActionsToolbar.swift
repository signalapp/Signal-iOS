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

    public enum MessageActionType: CaseIterable {
        case reply
        case copy
        case info
        case delete
        case share
        case save
        case forward
        case select
        case speak
        case stopSpeaking
        case edit
        case showPaymentDetails
        case endPoll
        case pin
        case unpin

        /// Lower priority numbers indicate an action should be shown earlier.
        var priority: Int {
            return switch self {
            case .reply: 0
            case .forward: 1
            case .edit: 2
            case .copy: 3
            case .share: 4
            case .save: 5
            case .endPoll: 6
            case .select: 7
            case .showPaymentDetails: 8
            case .speak: 9
            case .stopSpeaking: 10
            case .info: 11
            case .pin: 12
            case .unpin: 13
            case .delete: 14
            }
        }
    }

    let actionType: MessageActionType

    public init(
        _ actionType: MessageActionType,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        contextMenuTitle: String,
        contextMenuAttributes: ContextMenuAction.Attributes,
        block: @escaping (_ sender: Any?) -> Void,
    ) {
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
            case .save:
                return .contextMenuSave
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
            case .endPoll:
                return .pollStopLight
            case .pin:
                return .pin
            case .unpin:
                return .unpin
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

public class MessageActionsToolbar: UIView {

    weak var actionDelegate: MessageActionsToolbarDelegate?

    enum Mode {
        case normal(messagesActions: [MessageAction])
        case selection(
            deleteMessagesAction: MessageAction,
            forwardMessagesAction: MessageAction,
        )
    }

    private let mode: Mode

    private let toolbar = UIToolbar()

    init(mode: Mode) {
        self.mode = mode

        super.init(frame: .zero)

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)
        addConstraints([
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
        ])

        if #unavailable(iOS 26) {
            toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(themeDidChange),
                name: .themeDidChange,
                object: nil,
            )
        }

        updateContent()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    @objc
    @available(iOS, deprecated: 26)
    private func themeDidChange() {
        guard #unavailable(iOS 26) else { return }

        AssertIsOnMainThread()
        updateContent()
    }

    public func updateContent() {
        actionItems.removeAll()
        buildItems()
    }

    private func buildItems() {
        switch mode {
        case .normal(let messagesActions):
            buildNormalItems(messagesActions: messagesActions)
        case .selection(let deleteMessagesAction, let forwardMessagesAction):
            buildSelectionItems(
                deleteMessagesAction: deleteMessagesAction,
                forwardMessagesAction: forwardMessagesAction,
            )
        }
    }

    private var actionItems = [MessageAction.MessageActionType: UIBarButtonItem]()

    private func barButtonItem(for messageAction: MessageAction) -> UIBarButtonItem {
        let barButtonItem = UIBarButtonItem(
            image: messageAction.barButtonImage,
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                self.actionDelegate?.messageActionsToolbar(self, executedAction: messageAction)
            },
        )
        if #unavailable(iOS 26) {
            barButtonItem.tintColor = Theme.primaryIconColor
        }
        barButtonItem.accessibilityLabel = messageAction.accessibilityLabel
        return barButtonItem
    }

    private func buildNormalItems(messagesActions: [MessageAction]) {
        var newItems = [UIBarButtonItem]()

        for messageAction in messagesActions {
            if !newItems.isEmpty {
                newItems.append(.flexibleSpace())
            }

            let actionItem = barButtonItem(for: messageAction)
            newItems.append(actionItem)
            actionItems[messageAction.actionType] = actionItem
        }

        // If we only have a single button, center it.
        if newItems.count == 1 {
            newItems.insert(.flexibleSpace(), at: 0)
            newItems.append(.flexibleSpace())
        }

        toolbar.items = newItems
    }

    private func buildSelectionItems(
        deleteMessagesAction: MessageAction,
        forwardMessagesAction: MessageAction,
    ) {

        let deleteItem = barButtonItem(for: deleteMessagesAction)
        actionItems[deleteMessagesAction.actionType] = deleteItem

        let forwardItem = barButtonItem(for: forwardMessagesAction)
        actionItems[forwardMessagesAction.actionType] = forwardItem

        let selectedCount: Int = actionDelegate?.messageActionsToolbarSelectedInteractionCount ?? 0
        let labelFormat = OWSLocalizedString(
            "MESSAGE_ACTIONS_TOOLBAR_CAPTION_%d",
            tableName: "PluralAware",
            comment: "Label for the toolbar used in the multi-select mode. The number of selected items (1 or more) is passed.",
        )
        let labelTitle = String.localizedStringWithFormat(labelFormat, selectedCount)
        let label = UILabel()
        label.text = labelTitle
        if #available(iOS 26, *) {
            label.font = UIFont.dynamicTypeHeadlineClamped.monospaced()
        } else {
            label.font = UIFont.dynamicTypeBodyClamped.monospaced()
        }
        label.textColor = .Signal.label
        label.textAlignment = .center
        label.sizeToFit()
        let labelView: UIView = {
            // Add horizontal padding around text on iOS 26 because the item is displayed in a glass bubble.
            if #available(iOS 26, *) {
                let container = UIView()
                container.addSubview(label)
                label.translatesAutoresizingMaskIntoConstraints = false
                container.addConstraints([
                    label.topAnchor.constraint(equalTo: container.topAnchor),
                    label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                    label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                    label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
                return container
            } else {
                return label
            }
        }()
        let labelItem = UIBarButtonItem(customView: labelView)
        labelItem.isEnabled = false

        toolbar.items = [
            deleteItem,
            .flexibleSpace(),
            labelItem,
            .flexibleSpace(),
            forwardItem,
        ]
    }

    public func buttonItem(for actionType: MessageAction.MessageActionType) -> UIBarButtonItem? {
        guard let buttonItem = actionItems[actionType] else {
            owsFailDebug("Missing action item: \(actionType).")
            return nil
        }
        return buttonItem
    }
}

//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

class ChatColorViewController: OWSTableViewController2 {

    private let thread: TSThread?

    private var originalValue: ChatColorValue?
    private var currentValue: ChatColorValue?

    public init(thread: TSThread? = nil) {
        self.thread = thread

        super.init()

        self.originalValue = Self.databaseStorage.read { transaction in
            if let thread = self.thread {
                return ChatColors.chatColorSetting(thread: thread, transaction: transaction)
            } else {
                return ChatColors.defaultChatColorSetting(transaction: transaction)
            }
        }
        self.currentValue = self.originalValue

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: Wallpaper.wallpaperDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: ChatColors.chatColorsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(chatColorSettingDidChange),
            name: ChatColors.chatColorSettingDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: .ThemeDidChange,
            object: nil
        )
    }

    @objc
    private func chatColorSettingDidChange(_ notification: NSNotification) {
        guard let thread = self.thread else {
            return
        }
        guard let threadUniqueId = notification.userInfo?[ChatColors.chatColorSettingDidChangeThreadUniqueIdKey] as? String else {
            owsFailDebug("Missing threadUniqueId.")
            return
        }
        guard threadUniqueId == thread.uniqueId else {
            return
        }
        updateTableContents()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("CHAT_COLOR_SETTINGS_TITLE", comment: "Title for the chat color settings view.")

        navigationItem.rightBarButtonItem = .init(title: CommonStrings.setButton,
                                                  style: .done,
                                                  target: self,
                                                  action: #selector(didTapSet))

        updateTableContents()
    }

    private var hasUnsavedChanges: Bool {
        currentValue != originalValue
    }

    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateNavigation() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel),
            accessibilityIdentifier: "cancel_button"
        )

        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: CommonStrings.setButton,
                style: .done,
                target: self,
                action: #selector(didTapDone),
                accessibilityIdentifier: "set_button"
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc
    func updateTableContents() {
        let contents = OWSTableContents()

        let wallpaperPreviewView: UIView
        let hasWallpaper: Bool
        if let wallpaperView = (databaseStorage.read { transaction in
            Wallpaper.view(for: thread, transaction: transaction)
        }) {
            wallpaperPreviewView = wallpaperView.asPreviewView()
            hasWallpaper = true
        } else {
            wallpaperPreviewView = UIView()
            wallpaperPreviewView.backgroundColor = Theme.backgroundColor
            hasWallpaper = false
        }
        wallpaperPreviewView.layer.cornerRadius = OWSTableViewController2.cellRounding
        wallpaperPreviewView.clipsToBounds = true

        let mockConversationView = MockConversationView(
            model: buildMockConversationModel(),
            hasWallpaper: hasWallpaper,
            customChatColor: currentValue
        )
        let previewSection = OWSTableSection()
        previewSection.hasBackground = false
        previewSection.add(OWSTableItem { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            guard let self = self else { return cell }

            wallpaperPreviewView.setContentHuggingLow()
            wallpaperPreviewView.setCompressionResistanceLow()
            cell.contentView.addSubview(wallpaperPreviewView)
            wallpaperPreviewView.autoPinEdge(toSuperviewEdge: .left, withInset: self.cellHOuterLeftMargin)
            wallpaperPreviewView.autoPinEdge(toSuperviewEdge: .right, withInset: self.cellHOuterRightMargin)
            wallpaperPreviewView.autoPinHeightToSuperview()

            mockConversationView.setContentHuggingVerticalHigh()
            mockConversationView.setCompressionResistanceVerticalHigh()
            cell.contentView.addSubview(mockConversationView)
            mockConversationView.autoPinEdge(toSuperviewEdge: .left, withInset: self.cellHOuterLeftMargin)
            mockConversationView.autoPinEdge(toSuperviewEdge: .right, withInset: self.cellHOuterRightMargin)
            mockConversationView.autoPinEdge(toSuperviewEdge: .top, withInset: 24)
            mockConversationView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 24)

            return cell
        } actionBlock: {})
        contents.addSection(previewSection)

        let charColorPicker = buildChatColorPicker()
        let colorsSection = OWSTableSection()
        colorsSection.customHeaderHeight = 14
        colorsSection.add(OWSTableItem {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            cell.contentView.addSubview(charColorPicker)
            charColorPicker.autoPinEdgesToSuperviewMargins()
            return cell
        } actionBlock: {})
        contents.addSection(colorsSection)

        self.contents = contents

        updateNavigation()
    }

    func buildMockConversationModel() -> MockConversationView.MockModel {
        MockConversationView.MockModel(items: [
            .date,
            .incoming(text: NSLocalizedString(
                "CHAT_COLOR_INCOMING_MESSAGE",
                comment: "The incoming bubble text when setting a chat color."
            )),
            .outgoing(text: NSLocalizedString(
                "CHAT_COLOR_OUTGOING_MESSAGE",
                comment: "The outgoing bubble text when setting a chat color."
            ))
        ])
    }

    private enum Option {
        case auto
        case builtInValue(value: ChatColorValue)
        case customValue(value: ChatColorValue)
        case addNewOption

        static func allOptions(transaction: SDSAnyReadTransaction) -> [Option] {

            var result = [Option]()
            result.append(.auto)
            result.append(contentsOf: ChatColors.allValuesSorted.map { value in
                (value.isBuiltIn
                    ? Option.builtInValue(value: value)
                    : Option.customValue(value: value))
            })
            result.append(.addNewOption)

            return result
        }
    }

    private func showCustomColorView(valueMode: CustomColorViewController.ValueMode) {
        let customColorVC = CustomColorViewController(thread: thread,
                                                      valueMode: valueMode) { [weak self] (value) in
            guard let self = self else { return }
            Self.databaseStorage.write { transaction in
                Self.chatColors.upsertCustomValue(value, transaction: transaction)
            }
            self.currentValue = value
            self.updateTableContents()
        }
        self.navigationController?.pushViewController(customColorVC, animated: true)
    }

    private func showDeleteUI(_ value: ChatColorValue) {

        func deleteValue() {
            Self.databaseStorage.write { transaction in
                Self.chatColors.deleteCustomValue(value, transaction: transaction)
            }
        }

        let usageCount = databaseStorage.read { transaction in
            ChatColors.usageCount(forValue: value, transaction: transaction)
        }
        guard usageCount > 0 else {
            deleteValue()
            return
        }

        let message: String
        if usageCount > 1 {
            let messageFormat = NSLocalizedString("CHAT_COLOR_SETTINGS_DELETE_ALERT_MESSAGE_N_FORMAT",
                                                  comment: "Message for the 'delete chat color confirm alert' in the chat color settings view. Embeds: {{ the number of conversations that use this chat color }}.")
            message = String(format: messageFormat, OWSFormat.formatInt(usageCount))
        } else {
            message = NSLocalizedString("CHAT_COLOR_SETTINGS_DELETE_ALERT_MESSAGE_1",
                                        comment: "Message for the 'delete chat color confirm alert' in the chat color settings view.")
        }
        let actionSheet = ActionSheetController(
            title: NSLocalizedString("CHAT_COLOR_SETTINGS_DELETE_ALERT_TITLE",
                                     comment: "Title for the 'delete chat color confirm alert' in the chat color settings view."),
            message: message
        )

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.deleteButton
        ) { _ in
            deleteValue()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func duplicateValue(_ oldValue: ChatColorValue) {
        let newValue = ChatColorValue(id: ChatColorValue.randomId,
                                       appearance: oldValue.appearance,
                                       isBuiltIn: false)
        Self.databaseStorage.write { transaction in
            Self.chatColors.upsertCustomValue(newValue, transaction: transaction)
        }
    }

    private func didTapOption(option: Option) {
        switch option {
        case .auto:
            self.currentValue = nil
            updateTableContents()
        case .builtInValue(let value):
            self.currentValue = value
            updateTableContents()
        case .customValue(let value):
            if self.currentValue == value {
                showCustomColorView(valueMode: .editExisting(value: value))
            } else {
                self.currentValue = value
                updateTableContents()
            }
        case .addNewOption:
            showCustomColorView(valueMode: .createNew)
        }
    }

    private func didLongPressOption(option: Option) {
        switch option {
        case .auto, .builtInValue, .addNewOption:
            return
        case .customValue(let value):
            // TODO: Use new context menus when they are available.
            let actionSheet = ActionSheetController()

            let editAction = ActionSheetAction(
                title: CommonStrings.editButton
            ) { [weak self] _ in
                self?.showCustomColorView(valueMode: .editExisting(value: value))
            }
            editAction.trailingIcon = .compose24
            actionSheet.addAction(editAction)

            let duplicateAction = ActionSheetAction(
                title: NSLocalizedString("BUTTON_DUPLICATE",
                                         comment: "Label for the 'duplicate' button.")
            ) { [weak self] _ in
                self?.duplicateValue(value)
            }
            duplicateAction.trailingIcon = .copy24
            actionSheet.addAction(duplicateAction)

            let deleteAction = ActionSheetAction(
                title: CommonStrings.deleteButton
            ) { [weak self] _ in
                self?.showDeleteUI(value)
            }
            deleteAction.trailingIcon = .trash24
            actionSheet.addAction(deleteAction)

            actionSheet.addAction(OWSActionSheets.cancelAction)
            presentActionSheet(actionSheet)
        }
    }

    private func buildChatColorPicker() -> UIView {

        let hStackConfig = CVStackViewConfig(axis: .horizontal,
                                             alignment: .fill,
                                             spacing: 0,
                                             layoutMargins: .zero)
        let vStackConfig = CVStackViewConfig(axis: .vertical,
                                             alignment: .fill,
                                             spacing: 28,
                                             layoutMargins: .zero)

        let rowWidth: CGFloat = max(0, view.width - CGFloat(
            cellOuterInsets.totalWidth +
                OWSTableViewController2.cellHInnerMargin * 2 +
                hStackConfig.layoutMargins.totalWidth +
                vStackConfig.layoutMargins.totalWidth
        ))
        let optionViewInnerSize: CGFloat = 56
        let optionViewSelectionThickness: CGFloat = 4
        let optionViewSelectionSpacing: CGFloat = 2
        var optionViewOuterSize: CGFloat { optionViewInnerSize + 2 * optionViewSelectionThickness + 2 * optionViewSelectionSpacing }
        let optionViewMinHSpacing: CGFloat = 16
        let optionsPerRow = max(1, Int(floor(rowWidth + optionViewMinHSpacing) / (optionViewOuterSize + optionViewMinHSpacing)))

        var optionViews = [UIView]()
        databaseStorage.read { transaction in
            let options = Option.allOptions(transaction: transaction)
            for option in options {
                func addOptionView(innerView: UIView, isSelected: Bool) {

                    let outerView = OWSLayerView()
                    outerView.addTapGesture { [weak self] in
                        self?.didTapOption(option: option)
                    }
                    outerView.addLongPressGesture { [weak self] in
                        self?.didLongPressOption(option: option)
                    }
                    outerView.autoSetDimensions(to: .square(optionViewOuterSize))
                    outerView.setCompressionResistanceHigh()
                    outerView.setContentHuggingHigh()

                    outerView.addSubview(innerView)
                    innerView.autoSetDimensions(to: .square(optionViewInnerSize))
                    innerView.autoCenterInSuperview()

                    if isSelected {
                        let selectionView = OWSLayerView.circleView()
                        selectionView.layer.borderColor = Theme.primaryIconColor.cgColor
                        selectionView.layer.borderWidth = optionViewSelectionThickness
                        outerView.addSubview(selectionView)
                        selectionView.autoPinEdgesToSuperviewEdges()
                    }

                    optionViews.append(outerView)
                }
                switch option {
                case .auto:
                    let value = ChatColors.autoChatColor(forThread: self.thread, transaction: transaction)
                    let view = ChatColorSwatchView(chatColorValue: value, mode: .circle)

                    let label = UILabel()
                    label.text = NSLocalizedString("CHAT_COLOR_SETTINGS_AUTO",
                                                   comment: "Label for the 'automatic chat color' option in the chat color settings view.")
                    label.textColor = .ows_white
                    label.font = UIFont.systemFont(ofSize: 13)
                    label.adjustsFontSizeToFitWidth = true
                    view.addSubview(label)
                    label.autoCenterInSuperview()
                    label.autoPinEdge(toSuperviewEdge: .leading, withInset: 3, relation: .greaterThanOrEqual)
                    label.autoPinEdge(toSuperviewEdge: .trailing, withInset: 3, relation: .greaterThanOrEqual)

                    // nil represents auto.
                    addOptionView(innerView: view, isSelected: currentValue == nil)
                case .builtInValue(let value):
                    let view = ChatColorSwatchView(chatColorValue: value, mode: .circle)
                    addOptionView(innerView: view, isSelected: currentValue == value)
                case .customValue(let value):
                    let view = ChatColorSwatchView(chatColorValue: value, mode: .circle)

                    let imageView = UIImageView.withTemplateImageName("compose-solid-24", tintColor: .ows_white)
                    view.addSubview(imageView)
                    imageView.autoSetDimensions(to: .square(24))
                    imageView.autoCenterInSuperview()

                    addOptionView(innerView: view, isSelected: currentValue == value)
                case .addNewOption:
                    let view = OWSLayerView.circleView()
                    view.backgroundColor = Theme.washColor

                    let imageView = UIImageView.withTemplateImageName("plus-24", tintColor: Theme.primaryIconColor)
                    view.addSubview(imageView)
                    imageView.autoSetDimensions(to: .square(24))
                    imageView.autoCenterInSuperview()

                    addOptionView(innerView: view, isSelected: false)
                }
            }
        }

        var hStacks = [UIView]()
        while !optionViews.isEmpty {
            var hStackViews = [UIView]()
            while hStackViews.count < optionsPerRow,
                  !optionViews.isEmpty {
                let optionView = optionViews.removeFirst()
                hStackViews.append(optionView)
            }
            while hStackViews.count < optionsPerRow {
                let spacer = UIView.transparentSpacer()
                spacer.autoSetDimensions(to: .square(optionViewOuterSize))
                spacer.setCompressionResistanceHigh()
                spacer.setContentHuggingHigh()
                hStackViews.append(spacer)
            }
            let hStack = UIStackView(arrangedSubviews: hStackViews)
            hStack.apply(config: hStackConfig)
            hStack.distribution = .equalSpacing
            hStacks.append(hStack)
        }

        let vStack = UIStackView(arrangedSubviews: hStacks)
        vStack.apply(config: vStackConfig)
        return vStack
    }

    private func saveAndDismiss() {
        databaseStorage.write { transaction in
            if let thread = self.thread {
                ChatColors.setChatColorSetting(self.currentValue, thread: thread, transaction: transaction)
            } else {
                ChatColors.setDefaultChatColorSetting(self.currentValue, transaction: transaction)
            }
        }
        self.navigationController?.popViewController(animated: true)
    }

    private func dismissWithoutSaving() {
        self.navigationController?.popViewController(animated: true)
    }

    @objc
    func didTapSet() {
        saveAndDismiss()
    }

    @objc
    func didTapCancel() {
        guard hasUnsavedChanges else {
            dismissWithoutSaving()
            return
        }

        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            self?.dismissWithoutSaving()
        })
    }

    @objc
    func didTapDone() {
        saveAndDismiss()
    }
}

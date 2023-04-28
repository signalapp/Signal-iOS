//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

class ChatColorViewController: OWSTableViewController2 {

    fileprivate let thread: TSThread?

    fileprivate struct CurrentValue {
        // When we enter the view, "auto" should reflect the current resolved "auto" value,
        // not auto itself.
        //
        // Later, we should explicitly reflect the actions of the user.
        let selected: ChatColor?
        // Always render the current resolved value in the preview.
        let appearance: ChatColor
    }
    fileprivate var currentValue: CurrentValue

    private var chatColorPicker: ChatColorPicker?
    private var mockConversationView: MockConversationView?

    public init(thread: TSThread? = nil) {
        self.thread = thread

        self.currentValue = Self.databaseStorage.read { transaction in
            ChatColorViewController.buildCurrentValue_Initial(thread: thread, transaction: transaction)
        }

        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(wallpaperDidChange),
            name: Wallpaper.wallpaperDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(customChatColorsDidChange),
            name: ChatColors.customChatColorsDidChange,
            object: nil
        )
        if thread != nil {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(autoChatColorsDidChange),
                name: ChatColors.autoChatColorsDidChange,
                object: nil
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChangeNotification),
            name: .ThemeDidChange,
            object: nil
        )
    }

    @objc
    private func wallpaperDidChange() {
        updateTableContents()
    }

    @objc
    private func customChatColorsDidChange() {
        updateTableContents()
    }

    @objc
    private func autoChatColorsDidChange() {
        updateTableContents()
    }

    @objc
    private func themeDidChangeNotification() {
        updateTableContents()
    }

    private static func buildCurrentValue_Initial(thread: TSThread?,
                                                  transaction: SDSAnyReadTransaction) -> CurrentValue {
        let selected: ChatColor?
        let appearance: ChatColor
        if let thread = thread {
            selected = ChatColors.chatColorSetting(thread: thread,
                                                   shouldHonorDefaultSetting: false,
                                                   transaction: transaction)
            appearance = ChatColors.autoChatColorForRendering(forThread: thread,
                                                              transaction: transaction)
        } else {
            selected = ChatColors.defaultChatColorSetting(transaction: transaction)
            appearance = ChatColors.defaultChatColorForRendering(transaction: transaction)
        }
        return CurrentValue(selected: selected, appearance: appearance)
    }

    private static func buildCurrentValue_Update(thread: TSThread?,
                                                 selected: ChatColor?,
                                                 transaction: SDSAnyReadTransaction) -> CurrentValue {
        let appearance: ChatColor
        if let thread = thread {
            appearance = ChatColors.chatColorForRendering(thread: thread, transaction: transaction)
        } else {
            appearance = ChatColors.defaultChatColorForRendering(transaction: transaction)
        }
        return CurrentValue(selected: selected, appearance: appearance)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("CHAT_COLOR_SETTINGS_TITLE", comment: "Title for the chat color settings view.")

        updateTableContents()
    }

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
            customChatColor: currentValue.appearance
        )
        mockConversationView.delegate = self
        self.mockConversationView = mockConversationView
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

        let colorsSection = OWSTableSection()
        colorsSection.customHeaderHeight = 14
        colorsSection.add(OWSTableItem { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self = self else { return cell }

            cell.selectionStyle = .none
            let chatColorPicker = ChatColorPicker(chatColorViewController: self)
            self.chatColorPicker = chatColorPicker
            cell.contentView.addSubview(chatColorPicker)
            chatColorPicker.autoPinEdgesToSuperviewMargins()
            return cell
        } actionBlock: {})
        contents.addSection(colorsSection)

        self.contents = contents
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

    fileprivate enum Option {
        case auto
        case builtInValue(value: ChatColor)
        case customValue(value: ChatColor)
        case addNewOption

        var value: ChatColor? {
            switch self {
            case .auto:
                return nil
            case .builtInValue(let value):
                return value
            case .customValue(let value):
                return value
            case .addNewOption:
                return nil
            }
        }

        var canBeSelected: Bool {
            switch self {
            case .auto, .builtInValue, .customValue:
                return true
            case .addNewOption:
                return false
            }
        }

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
                                                      valueMode: valueMode) { [weak self] (value: ChatColor) in
            guard let self = self else { return }
            Self.databaseStorage.write { transaction in
                Self.chatColors.upsertCustomValue(value, transaction: transaction)
            }
            self.setNewValue(value)
        }
        self.navigationController?.pushViewController(customColorVC, animated: true)
    }

    private func showDeleteUI(_ value: ChatColor) {

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
        let messageFormat = NSLocalizedString("CHAT_COLOR_SETTINGS_DELETE_ALERT_MESSAGE_%d", tableName: "PluralAware",
                                              comment: "Message for the 'delete chat color confirm alert' in the chat color settings view. Embeds: {{ the number of conversations that use this chat color }}.")
        message = String.localizedStringWithFormat(messageFormat, usageCount)
        let actionSheet = ActionSheetController(
            title: NSLocalizedString("CHAT_COLOR_SETTINGS_DELETE_ALERT_TITLE",
                                     comment: "Title for the 'delete chat color confirm alert' in the chat color settings view."),
            message: message
        )

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.deleteButton
        ) { [weak self] _ in
            deleteValue()
            self?.updatePickerSelection()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func duplicateValue(_ oldValue: ChatColor) {
        let newValue = ChatColor(id: ChatColor.randomId,
                                 setting: oldValue.setting,
                                 isBuiltIn: false)
        Self.databaseStorage.write { transaction in
            Self.chatColors.upsertCustomValue(newValue, transaction: transaction)
        }
    }

    private func updatePickerSelection() {
        chatColorPicker?.selectionDidChange(chatColorViewController: self)
    }

    fileprivate func didTapOption(option: Option) {
        chatColorPicker?.dismissTooltip()

        switch option {
        case .auto:
            setNewValue(nil)
        case .builtInValue(let value):
            setNewValue(value)
        case .customValue(let value):
            if self.currentValue.selected == value {
                showCustomColorView(valueMode: .editExisting(value: value))
            } else {
                setNewValue(value)
            }
        case .addNewOption:
            showCustomColorView(valueMode: .createNew)
        }

        updatePickerSelection()
    }

    // TODO: Use new context menus when they are available.
    //       Until we do, hide the trailing icons.
    private let showTrailingIcons = false

    fileprivate func didLongPressOption(option: Option) {
        switch option {
        case .auto, .builtInValue, .addNewOption:
            return
        case .customValue(let value):
            let actionSheet = ActionSheetController()

            let editAction = ActionSheetAction(
                title: CommonStrings.editButton
            ) { [weak self] _ in
                self?.showCustomColorView(valueMode: .editExisting(value: value))
            }
            if showTrailingIcons {
                editAction.trailingIcon = .compose24
            }
            actionSheet.addAction(editAction)

            let duplicateAction = ActionSheetAction(
                title: NSLocalizedString("BUTTON_DUPLICATE",
                                         comment: "Label for the 'duplicate' button.")
            ) { [weak self] _ in
                self?.duplicateValue(value)
            }
            if showTrailingIcons {
                duplicateAction.trailingIcon = .copy24
            }
            actionSheet.addAction(duplicateAction)

            let deleteAction = ActionSheetAction(
                title: CommonStrings.deleteButton
            ) { [weak self] _ in
                self?.showDeleteUI(value)
            }
            if showTrailingIcons {
                deleteAction.trailingIcon = .trash24
            }
            actionSheet.addAction(deleteAction)

            actionSheet.addAction(OWSActionSheets.cancelAction)
            presentActionSheet(actionSheet)
        }
    }

    private func setNewValue(_ newValue: ChatColor?) {
        self.currentValue = databaseStorage.write { transaction in
            if let thread = self.thread {
                ChatColors.setChatColorSetting(newValue, thread: thread, transaction: transaction)
            } else {
                ChatColors.setDefaultChatColorSetting(newValue, transaction: transaction)
            }
            return ChatColorViewController.buildCurrentValue_Update(thread: thread,
                                                                    selected: newValue,
                                                                    transaction: transaction)
        }
        mockConversationView?.customChatColor = currentValue.appearance
    }
}

// MARK: -

extension ChatColorViewController: MockConversationDelegate {
    var mockConversationViewWidth: CGFloat {
        self.view.width - cellOuterInsets.totalWidth
    }
}

// MARK: -

private class ChatColorPicker: UIView {

    typealias Option = ChatColorViewController.Option

    private var optionViews = [OptionView]()

    init(chatColorViewController: ChatColorViewController) {
        super.init(frame: .zero)

        configure(chatColorViewController: chatColorViewController)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func selectionDidChange(chatColorViewController: ChatColorViewController) {
        for optionView in optionViews {
            optionView.isSelected = (optionView.option.canBeSelected &&
                                        optionView.option.value == chatColorViewController.currentValue.selected)
        }
    }

    private func configure(chatColorViewController: ChatColorViewController) {
        let hStackConfig = CVStackViewConfig(axis: .horizontal,
                                             alignment: .fill,
                                             spacing: 0,
                                             layoutMargins: .zero)
        let vStackConfig = CVStackViewConfig(axis: .vertical,
                                             alignment: .fill,
                                             spacing: 28,
                                             layoutMargins: .zero)

        let rowWidth: CGFloat = max(0,
                                    chatColorViewController.view.width - CGFloat(
                                        chatColorViewController.cellOuterInsets.totalWidth +
                                            OWSTableViewController2.cellHInnerMargin * 2 +
                                            hStackConfig.layoutMargins.totalWidth +
                                            vStackConfig.layoutMargins.totalWidth
        ))
        let optionViewInnerSize: CGFloat = 56
        let optionViewSelectionThickness: CGFloat = 4
        let optionViewSelectionSpacing: CGFloat = 2
        var optionViewOuterSize: CGFloat { optionViewInnerSize + 2 * optionViewSelectionThickness + 2 * optionViewSelectionSpacing }
        let optionViewMinHSpacing: CGFloat = 10
        let optionsPerRow = max(1, Int(floor(rowWidth + optionViewMinHSpacing) / (optionViewOuterSize + optionViewMinHSpacing)))

        var optionViews = [OptionView]()
        databaseStorage.read { transaction in
            let options = Option.allOptions(transaction: transaction)
            for option in options {
                func addOptionView(innerView: UIView, isSelected: Bool, selectionViews: [UIView] = []) {
                    let optionView = OptionView(chatColorViewController: chatColorViewController,
                                                option: option,
                                                innerView: innerView,
                                                selectionViews: selectionViews,
                                                isSelected: isSelected,
                                                optionViewInnerSize: optionViewInnerSize,
                                                optionViewOuterSize: optionViewOuterSize,
                                                optionViewSelectionThickness: optionViewSelectionThickness)
                    optionViews.append(optionView)
                }

                let currentValue = chatColorViewController.currentValue

                switch option {
                case .auto:
                    // We want the "auto" swatch in the global settings to ignore
                    // the global defaults, so that it is WYSIWYG.  If the user
                    // selects auto, the current global setting will no longer apply.
                    let thread = chatColorViewController.thread
                    let value = ChatColors.autoChatColorForRendering(forThread: thread,
                                                                     ignoreGlobalDefault: thread == nil,
                                                                     transaction: transaction)
                    let view = ColorOrGradientSwatchView(setting: value.setting, shapeMode: .circle)

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
                    addOptionView(innerView: view, isSelected: currentValue.selected == nil)
                case .builtInValue(let value):
                    let view = ColorOrGradientSwatchView(setting: value.setting, shapeMode: .circle)
                    addOptionView(innerView: view, isSelected: currentValue.selected == value)
                case .customValue(let value):
                    let view = ColorOrGradientSwatchView(setting: value.setting, shapeMode: .circle)

                    let isSelected = currentValue.selected == value

                    let editIconView = UIImageView.withTemplateImageName("compose-solid-24", tintColor: .ows_white)
                    view.addSubview(editIconView)
                    editIconView.autoSetDimensions(to: .square(24))
                    editIconView.autoCenterInSuperview()

                    addOptionView(innerView: view, isSelected: isSelected, selectionViews: [ editIconView ])
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

        self.optionViews = optionViews

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
        addSubview(vStack)
        vStack.autoPinEdgesToSuperviewEdges()

        ensureTooltip()
    }

    // MARK: -

    private class OptionView: OWSLayerView {

        let option: Option
        var isSelected: Bool {
            didSet {
                ensureSelectionViews()
            }
        }
        let optionViewInnerSize: CGFloat
        let optionViewOuterSize: CGFloat
        let optionViewSelectionThickness: CGFloat
        var selectionViews: [UIView] = []

        init(chatColorViewController: ChatColorViewController,
             option: Option,
             innerView: UIView,
             selectionViews: [UIView],
             isSelected: Bool,
             optionViewInnerSize: CGFloat,
             optionViewOuterSize: CGFloat,
             optionViewSelectionThickness: CGFloat) {

            self.option = option
            self.isSelected = isSelected
            self.optionViewInnerSize = optionViewInnerSize
            self.optionViewOuterSize = optionViewOuterSize
            self.optionViewSelectionThickness = optionViewSelectionThickness

            super.init()

            configure(chatColorViewController: chatColorViewController,
                      innerView: innerView,
                      selectionViews: selectionViews)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func configure(chatColorViewController: ChatColorViewController,
                               innerView: UIView,
                               selectionViews: [UIView]) {

            let option = self.option

            self.addTapGesture { [weak chatColorViewController] in
                chatColorViewController?.didTapOption(option: option)
            }
            self.addLongPressGesture { [weak chatColorViewController] in
                chatColorViewController?.didLongPressOption(option: option)
            }
            self.autoSetDimensions(to: .square(optionViewOuterSize))
            self.setCompressionResistanceHigh()
            self.setContentHuggingHigh()

            self.addSubview(innerView)
            innerView.autoSetDimensions(to: .square(optionViewInnerSize))
            innerView.autoCenterInSuperview()

            var selectionViews = selectionViews
            let selectionView = OWSLayerView.circleView()
            selectionView.layer.borderColor = Theme.primaryIconColor.cgColor
            selectionView.layer.borderWidth = optionViewSelectionThickness
            self.addSubview(selectionView)
            selectionView.autoPinEdgesToSuperviewEdges()
            selectionViews.append(selectionView)
            self.selectionViews = selectionViews

            ensureSelectionViews()
        }

        private func ensureSelectionViews() {
            for selectionView in selectionViews {
                selectionView.isHidden = !isSelected
            }
        }
    }

    // MARK: - Tooltip

    private static let keyValueStore = SDSKeyValueStore(collection: "ChatColorPicker")
    private static let tooltipWasDismissedKey = "tooltipWasDismissed"

    private var chatColorTooltip: ChatColorTooltip?

    fileprivate func dismissTooltip() {
        databaseStorage.write { transaction in
            Self.keyValueStore.setBool(true, key: Self.tooltipWasDismissedKey, transaction: transaction)
        }
        hideTooltip()
    }

    private func hideTooltip() {
        chatColorTooltip?.removeFromSuperview()
        chatColorTooltip = nil
    }

    private func ensureTooltip() {
        let shouldShowTooltip = databaseStorage.read { transaction in
            !Self.keyValueStore.getBool(Self.tooltipWasDismissedKey, defaultValue: false, transaction: transaction)
        }
        let isShowingTooltip = chatColorTooltip != nil
        guard shouldShowTooltip != isShowingTooltip else {
            return
        }
        if nil != self.chatColorTooltip {
            hideTooltip()
        } else {
            guard let autoOptionView = autoOptionView else {
                owsFailDebug("Missing autoOptionView.")
                hideTooltip()
                return
            }
            self.chatColorTooltip = ChatColorTooltip.present(fromView: self,
                                                             widthReferenceView: self,
                                                             tailReferenceView: autoOptionView) { [weak self] in
                self?.dismissTooltip()
            }
        }
    }

    private var autoOptionView: OptionView? {
        for optionView in optionViews {
            if case .auto = optionView.option {
                return optionView
            }
        }
        return nil
    }
}

// MARK: -

private class ChatColorTooltip: TooltipView {

    private override init(fromView: UIView,
                          widthReferenceView: UIView,
                          tailReferenceView: UIView,
                          wasTappedBlock: (() -> Void)?) {
        super.init(fromView: fromView,
                   widthReferenceView: widthReferenceView,
                   tailReferenceView: tailReferenceView,
                   wasTappedBlock: wasTappedBlock)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public class func present(fromView: UIView,
                              widthReferenceView: UIView,
                              tailReferenceView: UIView,
                              wasTappedBlock: (() -> Void)?) -> ChatColorTooltip {
        ChatColorTooltip(fromView: fromView,
                         widthReferenceView: widthReferenceView,
                         tailReferenceView: tailReferenceView,
                         wasTappedBlock: wasTappedBlock)
    }

    public override func bubbleContentView() -> UIView {
        let label = UILabel()
        label.text = NSLocalizedString("CHAT_COLORS_AUTO_TOOLTIP",
                                       comment: "Tooltip highlighting the auto chat color option.")
        label.font = .dynamicTypeSubheadline
        label.textColor = .ows_white
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return horizontalStack(forSubviews: [label])
    }

    public override var bubbleColor: UIColor {
        .ows_accentBlue
    }

    public override var tailDirection: TooltipView.TailDirection {
        .up
    }

    public override var bubbleInsets: UIEdgeInsets {
        UIEdgeInsets(hMargin: 12, vMargin: 7)
    }

    public override var bubbleHSpacing: CGFloat {
        10
    }
}

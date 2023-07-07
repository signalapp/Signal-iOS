//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

class ChatColorViewController: OWSTableViewController2, Dependencies {

    fileprivate let thread: TSThread?
    fileprivate var currentSetting: ChatColorSetting
    fileprivate var currentResolvedValue: ColorOrGradientSetting

    private var chatColorPicker: ChatColorPicker?
    private var mockConversationView: MockConversationView?

    public static func load(thread: TSThread?, tx: SDSAnyReadTransaction) -> ChatColorViewController {
        return ChatColorViewController(
            thread: thread,
            initialSetting: ChatColors.chatColorSetting(for: thread, tx: tx),
            initialResolvedValue: ChatColors.resolvedChatColor(for: thread, tx: tx)
        )
    }

    init(thread: TSThread?, initialSetting: ChatColorSetting, initialResolvedValue: ColorOrGradientSetting) {
        self.thread = thread
        self.currentSetting = initialSetting
        self.currentResolvedValue = initialResolvedValue

        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(wallpaperDidChange(notification:)),
            name: WallpaperStore.wallpaperDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(chatColorsDidChange),
            name: ChatColors.chatColorsDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChangeNotification),
            name: .themeDidChange,
            object: nil
        )
    }

    private var wallpaperViewBuilder: WallpaperViewBuilder?

    private func updateWallpaperViewBuilder() {
        wallpaperViewBuilder = databaseStorage.read { tx in Wallpaper.viewBuilder(for: thread, tx: tx) }
    }

    @objc
    private func wallpaperDidChange(notification: Notification) {
        guard notification.object == nil || (notification.object as? String) == thread?.uniqueId else { return }
        updateWallpaperViewBuilder()
        updateTableContents()
    }

    @objc
    private func chatColorsDidChange(_ notification: Notification) {
        guard notification.object == nil || (notification.object as? String) == thread?.uniqueId else { return }
        currentResolvedValue = databaseStorage.read { tx in ChatColors.resolvedChatColor(for: thread, tx: tx) }
        updateTableContents()
    }

    @objc
    private func themeDidChangeNotification() {
        updateTableContents()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("CHAT_COLOR_SETTINGS_TITLE", comment: "Title for the chat color settings view.")

        updateWallpaperViewBuilder()
        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let wallpaperPreviewView: UIView
        let hasWallpaper: Bool
        if let wallpaperViewBuilder {
            wallpaperPreviewView = wallpaperViewBuilder.build().asPreviewView()
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
            customChatColor: currentResolvedValue
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
        contents.add(previewSection)

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
        contents.add(colorsSection)

        self.contents = contents
    }

    func buildMockConversationModel() -> MockConversationView.MockModel {
        MockConversationView.MockModel(items: [
            .date,
            .incoming(text: OWSLocalizedString(
                "CHAT_COLOR_INCOMING_MESSAGE",
                comment: "The incoming bubble text when setting a chat color."
            )),
            .outgoing(text: OWSLocalizedString(
                "CHAT_COLOR_OUTGOING_MESSAGE",
                comment: "The outgoing bubble text when setting a chat color."
            ))
        ])
    }

    fileprivate enum Option {
        case chatColor(ChatColorSetting)
        case addNewOption

        static func allOptions(transaction tx: SDSAnyReadTransaction) -> [Option] {
            var result = [Option]()
            result.append(.chatColor(.auto))
            result.append(contentsOf: PaletteChatColor.allCases.map { .chatColor(.builtIn($0)) })
            result.append(contentsOf: chatColors.fetchCustomValues(tx: tx).map { .chatColor(.custom($0.key, $0.value)) })
            result.append(.addNewOption)
            return result
        }
    }

    private func showCustomColorView(valueMode: CustomColorViewController.ValueMode) {
        let viewController = CustomColorViewController(
            thread: thread,
            valueMode: valueMode,
            completion: { [weak self] (newValue: CustomChatColor) in
                guard let self = self else { return }
                let colorKey: CustomChatColor.Key
                switch valueMode {
                case .createNew:
                    colorKey = .generateRandom()
                case .editExisting(let key, value: _):
                    colorKey = key
                }
                self.databaseStorage.write { tx in
                    self.chatColors.upsertCustomValue(newValue, for: colorKey, tx: tx)
                }
                self.setNewValue(.custom(colorKey, newValue))
            }
        )
        self.navigationController?.pushViewController(viewController, animated: true)
    }

    private func deleteCustomColor(key: CustomChatColor.Key) {
        func deleteValue() {
            Self.databaseStorage.write { tx in
                Self.chatColors.deleteCustomValue(for: key, tx: tx)
            }
        }

        let usageCount = databaseStorage.read { tx in ChatColors.usageCount(for: key, tx: tx) }
        guard usageCount > 0 else {
            deleteValue()
            return
        }

        let message = String.localizedStringWithFormat(
            OWSLocalizedString(
                "CHAT_COLOR_SETTINGS_DELETE_ALERT_MESSAGE_%d",
                tableName: "PluralAware",
                comment: "Message for the 'delete chat color confirm alert' in the chat color settings view. Embeds: {{ the number of conversations that use this chat color }}."
            ),
            usageCount
        )
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "CHAT_COLOR_SETTINGS_DELETE_ALERT_TITLE",
                comment: "Title for the 'delete chat color confirm alert' in the chat color settings view."
            ),
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

    private func duplicateValue(_ oldValue: CustomChatColor) {
        let newValue = CustomChatColor(
            colorSetting: oldValue.colorSetting,
            creationTimestamp: NSDate.ows_millisecondTimeStamp()
        )
        databaseStorage.write { tx in
            chatColors.upsertCustomValue(newValue, for: .generateRandom(), tx: tx)
        }
    }

    private func updatePickerSelection() {
        chatColorPicker?.updateSelectedView(chatColorViewController: self)
    }

    fileprivate func didTapOption(option: Option) {
        chatColorPicker?.dismissTooltip()

        switch option {
        case .chatColor(let chatColorSetting):
            if currentSetting == chatColorSetting, case .custom(let key, let value) = chatColorSetting {
                showCustomColorView(valueMode: .editExisting(key: key, value: value))
            } else {
                setNewValue(chatColorSetting)
                updatePickerSelection()
            }
        case .addNewOption:
            showCustomColorView(valueMode: .createNew)
        }
    }

    // TODO: Use new context menus when they are available.
    fileprivate func didLongPressOption(option: Option) {
        switch option {
        case .chatColor(.auto), .chatColor(.builtIn), .addNewOption:
            return
        case .chatColor(.custom(let key, let value)):
            let actionSheet = ActionSheetController()

            let editAction = ActionSheetAction(
                title: CommonStrings.editButton
            ) { [weak self] _ in
                self?.showCustomColorView(valueMode: .editExisting(key: key, value: value))
            }
            actionSheet.addAction(editAction)

            let duplicateAction = ActionSheetAction(
                title: OWSLocalizedString("BUTTON_DUPLICATE", comment: "Label for the 'duplicate' button.")
            ) { [weak self] _ in
                self?.duplicateValue(value)
            }
            actionSheet.addAction(duplicateAction)

            let deleteAction = ActionSheetAction(
                title: CommonStrings.deleteButton
            ) { [weak self] _ in
                self?.deleteCustomColor(key: key)
            }
            actionSheet.addAction(deleteAction)

            actionSheet.addAction(OWSActionSheets.cancelAction)
            presentActionSheet(actionSheet)
        }
    }

    private func setNewValue(_ newValue: ChatColorSetting) {
        databaseStorage.write { tx in ChatColors.setChatColorSetting(newValue, for: thread, tx: tx) }
        currentSetting = newValue
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

    fileprivate func updateSelectedView(chatColorViewController: ChatColorViewController) {
        for optionView in optionViews {
            optionView.isSelected = { () -> Bool in
                if case .chatColor(let chatColor) = optionView.option, chatColor == chatColorViewController.currentSetting {
                    return true
                }
                return false
            }()
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
                func addOptionView(innerView: UIView, selectionViews: [UIView] = []) {
                    let optionView = OptionView(
                        chatColorViewController: chatColorViewController,
                        option: option,
                        innerView: innerView,
                        selectionViews: selectionViews,
                        optionViewInnerSize: optionViewInnerSize,
                        optionViewOuterSize: optionViewOuterSize,
                        optionViewSelectionThickness: optionViewSelectionThickness
                    )
                    optionViews.append(optionView)
                }

                switch option {
                case .chatColor(.auto):
                    let value = ChatColors.autoChatColor(for: chatColorViewController.thread, tx: transaction)
                    let view = ColorOrGradientSwatchView(setting: value, shapeMode: .circle)

                    let label = UILabel()
                    label.text = OWSLocalizedString("CHAT_COLOR_SETTINGS_AUTO",
                                                   comment: "Label for the 'automatic chat color' option in the chat color settings view.")
                    label.textColor = .ows_white
                    label.font = UIFont.systemFont(ofSize: 13)
                    label.adjustsFontSizeToFitWidth = true
                    view.addSubview(label)
                    label.autoCenterInSuperview()
                    label.autoPinEdge(toSuperviewEdge: .leading, withInset: 3, relation: .greaterThanOrEqual)
                    label.autoPinEdge(toSuperviewEdge: .trailing, withInset: 3, relation: .greaterThanOrEqual)
                    addOptionView(innerView: view)
                case .chatColor(.builtIn(let paletteColor)):
                    let view = ColorOrGradientSwatchView(setting: paletteColor.colorSetting, shapeMode: .circle)
                    addOptionView(innerView: view)
                case .chatColor(.custom(_, let customColor)):
                    let view = ColorOrGradientSwatchView(setting: customColor.colorSetting, shapeMode: .circle)
                    let editIconView = UIImageView(image: UIImage(imageLiteralResourceName: "edit-fill"))
                    editIconView.tintColor = .white
                    view.addSubview(editIconView)
                    editIconView.autoSetDimensions(to: .square(24))
                    editIconView.autoCenterInSuperview()
                    addOptionView(innerView: view, selectionViews: [ editIconView ])
                case .addNewOption:
                    let view = OWSLayerView.circleView()
                    view.backgroundColor = Theme.washColor
                    let imageView = UIImageView.withTemplateImageName("plus-bold", tintColor: Theme.primaryIconColor)
                    view.addSubview(imageView)
                    imageView.autoSetDimensions(to: .square(24))
                    imageView.autoCenterInSuperview()
                    addOptionView(innerView: view)
                }
            }
        }

        self.optionViews = optionViews
        updateSelectedView(chatColorViewController: chatColorViewController)

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
        var isSelected: Bool = false {
            didSet {
                ensureSelectionViews()
            }
        }
        let optionViewInnerSize: CGFloat
        let optionViewOuterSize: CGFloat
        let optionViewSelectionThickness: CGFloat
        var selectionViews: [UIView] = []

        init(
            chatColorViewController: ChatColorViewController,
            option: Option,
            innerView: UIView,
            selectionViews: [UIView],
            optionViewInnerSize: CGFloat,
            optionViewOuterSize: CGFloat,
            optionViewSelectionThickness: CGFloat
        ) {
            self.option = option
            self.optionViewInnerSize = optionViewInnerSize
            self.optionViewOuterSize = optionViewOuterSize
            self.optionViewSelectionThickness = optionViewSelectionThickness

            super.init()

            configure(
                chatColorViewController: chatColorViewController,
                innerView: innerView,
                selectionViews: selectionViews
            )
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func configure(
            chatColorViewController: ChatColorViewController,
            innerView: UIView,
            selectionViews: [UIView]
        ) {
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
        if shouldShowTooltip == isShowingTooltip {
            return
        }
        if self.chatColorTooltip != nil {
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
            if case .chatColor(.auto) = optionView.option {
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
        label.text = OWSLocalizedString("CHAT_COLORS_AUTO_TOOLTIP",
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

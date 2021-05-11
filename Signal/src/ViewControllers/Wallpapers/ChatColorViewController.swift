//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class ChatColorViewController: OWSTableViewController2 {

    private let thread: TSThread?

    public init(thread: TSThread? = nil) {
        self.thread = thread
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: Wallpaper.wallpaperDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: ChatColors.defaultChatColorDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(chatColorDidChange),
            name: ChatColors.chatColorDidChange,
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
    private func chatColorDidChange(_ notification: NSNotification) {
        guard let thread = self.thread else {
            return
        }
        guard let threadUniqueId = notification.userInfo?[ChatColors.chatColorDidChangeThreadUniqueIdKey] as? String else {
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

        updateTableContents()
    }

    @objc
    func updateTableContents() {
        let contents = OWSTableContents()

        let wallpaperPreviewView: UIView
        if let wallpaperView = (databaseStorage.read { transaction in
            Wallpaper.view(for: thread, transaction: transaction)
        }) {
            wallpaperPreviewView = wallpaperView.asPreviewView()
        } else {
            wallpaperPreviewView = UIView()
            wallpaperPreviewView.backgroundColor = Theme.backgroundColor
        }
        wallpaperPreviewView.layer.cornerRadius = OWSTableViewController2.cellRounding
        wallpaperPreviewView.clipsToBounds = true

        let mockConversationView = MockConversationView(
            mode: buildMockConversationMode(),
            hasWallpaper: true
        )
        let previewSection = OWSTableSection()
        previewSection.hasBackground = false
        previewSection.add(OWSTableItem { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            guard let self = self else { return cell }

            cell.contentView.addSubview(wallpaperPreviewView)
            wallpaperPreviewView.autoPinEdge(toSuperviewEdge: .left, withInset: self.cellHOuterLeftMargin)
            wallpaperPreviewView.autoPinEdge(toSuperviewEdge: .right, withInset: self.cellHOuterRightMargin)
            wallpaperPreviewView.autoPinHeightToSuperview()

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
    }

    func buildMockConversationMode() -> MockConversationView.Mode {
        let outgoingText = NSLocalizedString(
            "CHAT_COLOR_OUTGOING_MESSAGE",
            comment: "The outgoing bubble text when setting a chat color."
        )
        let incomingText = NSLocalizedString(
            "CHAT_COLOR_INCOMING_MESSAGE",
            comment: "The incoming bubble text when setting a chat color."
        )
        return .dateIncomingOutgoing(
            incomingText: incomingText,
            outgoingText: outgoingText
        )
    }

    private enum Option {
        case auto
        case builtInValue(value: ChatColorValue)
        case customValue(value: ChatColorValue)
        case addNewOption

        static func allOptions(transaction: SDSAnyReadTransaction) -> [Option] {
            var result = [Option]()
            result.append(.auto)
            result.append(contentsOf: ChatColors.builtInValues.map {
                Option.builtInValue(value: $0)
            })
            result.append(contentsOf: ChatColors.customValues(transaction: transaction).map {
                Option.builtInValue(value: $0)
            })
            result.append(.addNewOption)

            return result
        }
    }

    struct Queue<T> {
        private var items: [T] = []

        var isEmpty: Bool { items.isEmpty }

        mutating func append(_ item: T) {
            items.append(item)
        }

        mutating func popHead() -> T? {
            guard let item = items.first else {
                return nil
            }
            items.remove(at: 0)
            return item
        }
    }

    private func didTapOption(option: Option) {
        // TODO:
        Logger.verbose("----")
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
        let optionViewOuterSize: CGFloat = 62
        let optionViewMinHSpacing: CGFloat = 16
        let optionsPerRow = max(1, Int(floor(rowWidth + optionViewMinHSpacing) / (optionViewOuterSize + optionViewMinHSpacing)))

        var optionViews = Queue<UIView>()
        databaseStorage.read { transaction in
            let currentValue: ChatColorValue?
            if let thread = self.thread {
                currentValue = ChatColors.chatColorSetting(thread: thread, transaction: transaction)
            } else {
                currentValue = ChatColors.defaultChatColorSetting(transaction: transaction)
            }

            let options = Option.allOptions(transaction: transaction)
            for option in options {
                func addOptionView(innerView: UIView, isSelected: Bool) {

                    let outerView = OWSLayerView()
                    outerView.addTapGesture { [weak self] in
                        self?.didTapOption(option: option)
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
                        selectionView.layer.borderWidth = 2
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
                    label.layer.shadowColor = UIColor.ows_black.cgColor
                    label.layer.shadowOffset = .zero
                    label.layer.shadowOpacity = 0.2
                    label.layer.shadowRadius = 2
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
                  let optionView = optionViews.popHead() {
                hStackViews.append(optionView)
            }
            while hStackViews.count < optionsPerRow {
                hStackViews.append(UIView.transparentSpacer())
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
}

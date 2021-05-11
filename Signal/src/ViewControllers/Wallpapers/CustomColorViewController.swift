//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public protocol CustomColorViewDelegate: class {
    func didSetCustomColor(value: ChatColorValue)
}

// MARK: -

public class CustomColorViewController: OWSTableViewController2 {

    private let thread: TSThread?

    private weak var customColorViewDelegate: CustomColorViewDelegate?

    private let modeControl = UISegmentedControl()

    private enum Mode: Int {
        case solid = 0
        case gradient = 1
    }

    private var mode: Mode = .solid {
        didSet {
            updateTableContents()
        }
    }

    public init(thread: TSThread? = nil,
                customColorViewDelegate: CustomColorViewDelegate) {
        self.thread = thread
        self.customColorViewDelegate = customColorViewDelegate

        super.init()

        topHeader = OWSTableViewController2.buildTopHeader(forView: modeControl,
                                                           vMargin: 10)

//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(updateTableContents),
//            name: Wallpaper.wallpaperDidChangeNotification,
//            object: nil
//        )
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(updateTableContents),
//            name: ChatColors.autoChatColorDidChange,
//            object: nil
//        )
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(chatColorDidChange),
//            name: ChatColors.chatColorDidChange,
//            object: nil
//        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: .ThemeDidChange,
            object: nil
        )
    }

//    @objc
//    private func chatColorDidChange(_ notification: NSNotification) {
//        guard let thread = self.thread else {
//            return
//        }
//        guard let threadUniqueId = notification.userInfo?[ChatColors.chatColorDidChangeThreadUniqueIdKey] as? String else {
//            owsFailDebug("Missing threadUniqueId.")
//            return
//        }
//        guard threadUniqueId == thread.uniqueId else {
//            return
//        }
//        updateTableContents()
//    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("CUSTOM_CHAT_COLOR_SETTINGS_TITLE",
                                  comment: "Title for the custom chat color settings view.")

        createSubviews()

        updateTableContents()
    }

    private func createSubviews() {
        modeControl.insertSegment(withTitle: NSLocalizedString("CUSTOM_CHAT_COLOR_SETTINGS_SOLID_COLOR",
                                                               comment: "Label for the 'solid color' mode in the custom chat color settings view."),
                                  at: Mode.solid.rawValue,
                                  animated: false)
        modeControl.insertSegment(withTitle: NSLocalizedString("CUSTOM_CHAT_COLOR_SETTINGS_GRADIENT",
                                                               comment: "Label for the 'gradient' mode in the custom chat color settings view."),
                                  at: Mode.gradient.rawValue,
                                  animated: false)
        modeControl.selectedSegmentIndex = mode.rawValue
        modeControl.addTarget(self,
                              action: #selector(modeControlDidChange),
                              for: .valueChanged)
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

//        let charColorPicker = buildChatColorPicker()
//        let colorsSection = OWSTableSection()
//        colorsSection.customHeaderHeight = 14
//        colorsSection.add(OWSTableItem {
//            let cell = OWSTableItem.newCell()
//            cell.selectionStyle = .none
//            cell.contentView.addSubview(charColorPicker)
//            charColorPicker.autoPinEdgesToSuperviewMargins()
//            return cell
//        } actionBlock: {})
//        contents.addSection(colorsSection)

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

    // MARK: - Events

    @objc
    private func modeControlDidChange(_ sender: UISegmentedControl) {
        guard let mode = Mode(rawValue: sender.selectedSegmentIndex) else {
            owsFailDebug("Couldn't update recordType.")
            return
        }
        self.mode = mode
    }
}

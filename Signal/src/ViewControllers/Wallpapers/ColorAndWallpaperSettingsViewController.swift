//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

public class ColorAndWallpaperSettingsViewController: OWSTableViewController2 {
    let thread: TSThread?
    public init(thread: TSThread? = nil) {
        self.thread = thread
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(wallpaperDidChange(notification:)),
            name: WallpaperStore.wallpaperDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: ChatColors.customChatColorsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: ChatColors.autoChatColorsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(conversationChatColorSettingDidChange),
            name: ChatColors.conversationChatColorSettingDidChange,
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
    private func conversationChatColorSettingDidChange(_ notification: NSNotification) {
        guard let thread = self.thread else {
            return
        }
        guard let threadUniqueId = notification.userInfo?[ChatColors.conversationChatColorSettingDidChangeThreadUniqueIdKey] as? String else {
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

        title = OWSLocalizedString("COLOR_AND_WALLPAPER_SETTINGS_TITLE", comment: "Title for the color & wallpaper settings view.")

        updateWallpaperViewBuilder()
        updateTableContents()
    }

    @objc
    func updateTableContents() {
        let contents = OWSTableContents()

        let previewSection = OWSTableSection()
        previewSection.hasBackground = false
        let previewItem = OWSTableItem { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            guard let self = self else { return cell }
            let miniPreview = MiniPreviewView(thread: self.thread, wallpaperViewBuilder: self.wallpaperViewBuilder)
            cell.contentView.addSubview(miniPreview)
            miniPreview.autoPinEdge(toSuperviewEdge: .left, withInset: self.cellHOuterLeftMargin)
            miniPreview.autoPinEdge(toSuperviewEdge: .right, withInset: self.cellHOuterRightMargin)
            miniPreview.autoPinHeightToSuperview()
            return cell
        } actionBlock: {}
        previewSection.add(previewItem)

        contents.add(previewSection)

        do {
            let chatColorSection = OWSTableSection()
            chatColorSection.customHeaderHeight = 14

            let chatColor: ChatColor
            if let thread = self.thread {
                chatColor = Self.databaseStorage.read { transaction in
                    ChatColors.chatColorForRendering(thread: thread, transaction: transaction)
                }
            } else {
                chatColor = Self.databaseStorage.read { transaction in
                    ChatColors.defaultChatColorForRendering(transaction: transaction)
                }
            }
            let defaultColorView = ColorOrGradientSwatchView(setting: chatColor.setting, shapeMode: .circle)
            defaultColorView.autoSetDimensions(to: .square(16))
            defaultColorView.setContentHuggingHigh()
            defaultColorView.setCompressionResistanceHigh()
            chatColorSection.add(.item(
                name: OWSLocalizedString("WALLPAPER_SETTINGS_SET_CHAT_COLOR",
                                        comment: "Set chat color action in color and wallpaper settings view."),
                accessoryType: .disclosureIndicator,
                accessoryContentView: defaultColorView,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "set_chat_color")
            ) { [weak self] in
                guard let self = self else { return }
                let vc = ChatColorViewController(thread: self.thread)
                self.navigationController?.pushViewController(vc, animated: true)
            })

            if nil != thread {
                chatColorSection.add(.item(
                    name: OWSLocalizedString(
                        "WALLPAPER_SETTINGS_RESET_CONVERSATION_CHAT_COLOR",
                        comment: "Reset conversation chat color action in wallpaper settings view."
                    ),
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "reset_chat_color")
                ) { [weak self] in
                    self?.didPressResetConversationChatColor()
                })
            } else {
                chatColorSection.add(.item(
                    name: OWSLocalizedString(
                        "WALLPAPER_SETTINGS_RESET_DEFAULT_CHAT_COLORS",
                        comment: "Reset global chat colors action in wallpaper settings view."
                    ),
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "reset_chat_colors")
                ) { [weak self] in
                    self?.didPressResetGlobalChatColors()
                })
            }

            contents.add(chatColorSection)
        }

        let wallpaperSection = OWSTableSection()
        wallpaperSection.customHeaderHeight = 14

        wallpaperSection.add(OWSTableItem.disclosureItem(
            withText: OWSLocalizedString("WALLPAPER_SETTINGS_SET_WALLPAPER",
                                        comment: "Set wallpaper action in wallpaper settings view."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "set_wallpaper")
        ) { [weak self] in
            guard let self = self else { return }
            let viewController = self.databaseStorage.read { tx in
                SetWallpaperViewController.load(thread: self.thread, tx: tx)
            }
            self.navigationController?.pushViewController(viewController, animated: true)
        })

        wallpaperSection.add(OWSTableItem.switch(
            withText: OWSLocalizedString("WALLPAPER_SETTINGS_DIM_WALLPAPER",
                                        comment: "Dim wallpaper action in wallpaper settings view."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "dim_wallpaper"),
            isOn: { () -> Bool in
                self.databaseStorage.read { Wallpaper.dimInDarkMode(for: self.thread, transaction: $0) }
            },
            isEnabled: {
                self.databaseStorage.read { Wallpaper.wallpaperForRendering(for: self.thread, transaction: $0) != nil }
            },
            target: self,
            selector: #selector(updateWallpaperDimming)
        ))

        if nil != thread {
            wallpaperSection.add(.item(
                name: OWSLocalizedString(
                    "WALLPAPER_SETTINGS_RESET_CONVERSATION_WALLPAPER",
                    comment: "Reset conversation wallpaper action in wallpaper settings view."
                ),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "reset_wallpaper")
            ) { [weak self] in
                self?.didPressResetConversationWallpaper()
            })
        } else {
            wallpaperSection.add(.item(
                name: OWSLocalizedString(
                    "WALLPAPER_SETTINGS_RESET_GLOBAL_WALLPAPER",
                    comment: "Reset wallpapers action in wallpaper settings view."
                ),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "reset_wallpapers")
            ) { [weak self] in
                self?.didPressResetGlobalWallpapers()
            })
        }

        contents.add(wallpaperSection)

        self.contents = contents
    }

    @objc
    func updateWallpaperDimming(_ sender: UISwitch) {
        databaseStorage.asyncWrite { tx in
            let wallpaperStore = DependenciesBridge.shared.wallpaperStore
            wallpaperStore.setDimInDarkMode(sender.isOn, for: self.thread?.uniqueId, tx: tx.asV2Write)
        }
    }

    // MARK: - Reset Wallpapers

    func didPressResetConversationWallpaper() {
        owsAssertDebug(thread != nil)

        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString("WALLPAPER_SETTINGS_CLEAR_WALLPAPER_CHAT_CONFIRMATION",
                                     comment: "Confirmation dialog when clearing the wallpaper for a specific chat."),
            proceedTitle: OWSLocalizedString(
                "WALLPAPER_SETTINGS_CLEAR_WALLPAPER",
                comment: "Clear wallpaper action in wallpaper settings view."
            ),
            proceedStyle: .destructive
        ) { _ in
            self.resetWallpaper()
        }
    }

    func didPressResetGlobalWallpapers() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString("WALLPAPER_SETTINGS_RESET_WALLPAPERS_CONFIRMATION_TITLE",
                                     comment: "Title of confirmation dialog when resetting the global wallpaper settings."),
            message: OWSLocalizedString("WALLPAPER_SETTINGS_RESET_WALLPAPERS_CONFIRMATION_MESSAGE",
                                       comment: "Message of confirmation dialog when resetting the global wallpaper settings.")
        )

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("WALLPAPER_SETTINGS_RESET_DEFAULT_WALLPAPER",
                                     comment: "Label for 'reset default wallpaper' action in the global wallpaper settings.")) { [weak self] _ in
            self?.resetWallpaper()
        })

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("WALLPAPER_SETTINGS_RESET_ALL_WALLPAPERS",
                                     comment: "Label for 'reset all wallpapers' action in the global wallpaper settings.")) { [weak self] _ in
            self?.resetAllWallpapers()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    func resetWallpaper() {
        let thread = self.thread
        databaseStorage.asyncWrite { tx in
            do {
                let wallpaperStore = DependenciesBridge.shared.wallpaperStore
                try wallpaperStore.reset(for: thread, tx: tx.asV2Write)
            } catch {
                owsFailDebug("Failed to clear wallpaper with error: \(error)")
                DispatchQueue.main.async {
                    OWSActionSheets.showErrorAlert(
                        message: OWSLocalizedString("WALLPAPER_SETTINGS_FAILED_TO_CLEAR",
                                                   comment: "An error indicating to the user that we failed to clear the wallpaper.")
                    )
                }
            }
            tx.addAsyncCompletionOnMain {
                self.updateTableContents()
            }
        }
    }

    private func resetAllWallpapers() {
        databaseStorage.asyncWrite { tx in
            do {
                let wallpaperStore = DependenciesBridge.shared.wallpaperStore
                try wallpaperStore.resetAll(tx: tx.asV2Write)
            } catch {
                owsFailDebug("Failed to reset all wallpapers with error: \(error)")
                DispatchQueue.main.async {
                    OWSActionSheets.showErrorAlert(
                        message: OWSLocalizedString("WALLPAPER_SETTINGS_FAILED_TO_RESET",
                                                   comment: "An error indicating to the user that we failed to reset all wallpapers.")
                    )
                }
            }
            tx.addAsyncCompletionOnMain {
                self.updateTableContents()
            }
        }
    }

    // MARK: - Reset Chat Colors

    func didPressResetConversationChatColor() {
        owsAssertDebug(thread != nil)

        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString("WALLPAPER_SETTINGS_CLEAR_CHAT_COLOR_CHAT_CONFIRMATION",
                                     comment: "Confirmation dialog when clearing the chat color for a specific chat."),
            proceedTitle: OWSLocalizedString(
                "WALLPAPER_SETTINGS_CLEAR_CHAT_COLOR",
                comment: "Clear chat color action in wallpaper settings view."
            ),
            proceedStyle: .destructive
        ) { _ in
            self.resetChatColor()
        }
    }

    func didPressResetGlobalChatColors() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString("WALLPAPER_SETTINGS_RESET_CHAT_COLORS_CONFIRMATION_TITLE",
                                     comment: "Title of confirmation dialog when resetting the global wallpaper settings."),
            message: OWSLocalizedString("WALLPAPER_SETTINGS_RESET_CHAT_COLORS_CONFIRMATION_MESSAGE",
                                       comment: "Message of confirmation dialog when resetting the global wallpaper settings.")
        )

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("WALLPAPER_SETTINGS_RESET_DEFAULT_CHAT_COLOR",
                                     comment: "Label for 'reset default chat color' action in the global wallpaper settings.")) { [weak self] _ in
            self?.resetChatColor()
        })

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("WALLPAPER_SETTINGS_RESET_ALL_CHAT_COLORS",
                                     comment: "Label for 'reset all chat colors' action in the global wallpaper settings.")) { [weak self] _ in
            self?.resetAllChatColors()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    func resetChatColor() {
        let thread = self.thread
        databaseStorage.asyncWrite { transaction in
            if let thread = thread {
                ChatColors.setChatColorSetting(nil, thread: thread, transaction: transaction)
            } else {
                ChatColors.setDefaultChatColorSetting(nil, transaction: transaction)
            }
            transaction.addAsyncCompletionOnMain {
                AssertIsOnMainThread()

                self.updateTableContents()
            }
        }
    }

    private func resetAllChatColors() {
        databaseStorage.asyncWrite { transaction in
            ChatColors.resetAllSettings(transaction: transaction)

            transaction.addAsyncCompletionOnMain {
                AssertIsOnMainThread()

                self.updateTableContents()
            }
        }
    }
}

// MARK: -

private class MiniPreviewView: UIView {
    private let thread: TSThread?
    private let hasWallpaper: Bool

    init(thread: TSThread?, wallpaperViewBuilder: WallpaperViewBuilder?) {
        self.thread = thread

        let hasWallpaper: Bool
        let stackViewContainer: UIView
        if let wallpaperViewBuilder {
            stackViewContainer = wallpaperViewBuilder.build().asPreviewView()
            hasWallpaper = true
        } else {
            stackViewContainer = UIView()
            stackViewContainer.backgroundColor = Theme.backgroundColor
            hasWallpaper = false
        }
        self.hasWallpaper = hasWallpaper

        super.init(frame: .zero)

        layer.cornerRadius = OWSTableViewController2.cellRounding
        backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray05

        stackViewContainer.layer.cornerRadius = 8
        stackViewContainer.clipsToBounds = true

        let windowAspectRatio = CGSize(
            width: CurrentAppContext().frame.size.smallerAxis,
            height: CurrentAppContext().frame.size.largerAxis
        ).aspectRatio

        stackViewContainer.autoSetDimensions(
            to: CGSize(
                width: 156,
                height: 156 / windowAspectRatio
            )
        )

        addSubview(stackViewContainer)
        stackViewContainer.autoHCenterInSuperview()
        stackViewContainer.autoPinHeightToSuperview(withMargin: 16)

        let stackView = UIStackView(
            arrangedSubviews: [
                buildHeaderPreview(),
                .spacer(withHeight: 12),
                buildDateHeader(),
                .spacer(withHeight: 8),
                buildIncomingBubble(),
                .spacer(withHeight: 6),
                buildOutgoingBubble(),
                .vStretchingSpacer(),
                buildComposerPreview()
            ]
        )
        stackView.axis = .vertical

        stackViewContainer.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
    }

    func buildDateHeader() -> UIView {
        let containerView = UIView()
        let pillView = PillView()
        pillView.autoSetDimensions(to: CGSize(width: 24, height: 10))
        pillView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_gray05
        containerView.addSubview(pillView)
        pillView.autoHCenterInSuperview()
        pillView.autoPinHeightToSuperview()
        return containerView
    }

    func buildIncomingBubble() -> UIView {
        let containerView = UIView()
        let bubbleView = UIView()
        bubbleView.layer.cornerRadius = 10
        bubbleView.autoSetDimensions(to: CGSize(width: 100, height: 30))
        bubbleView.backgroundColor = ConversationStyle.bubbleColorIncoming(hasWallpaper: hasWallpaper,
                                                                           isDarkThemeEnabled: Theme.isDarkThemeEnabled)
        containerView.addSubview(bubbleView)
        bubbleView.autoPinEdge(toSuperviewEdge: .leading, withInset: 8)
        bubbleView.autoPinHeightToSuperview()
        return containerView
    }

    func buildOutgoingBubble() -> UIView {
        let chatColor: ChatColor = databaseStorage.read { transaction in
            if let thread = self.thread {
                return ChatColors.chatColorForRendering(thread: thread,
                                                        transaction: transaction)
            } else {
                return ChatColors.defaultChatColorForRendering(transaction: transaction)
            }
        }
        let chatColorView = CVColorOrGradientView()
        chatColorView.configure(value: chatColor.setting.asValue, referenceView: self)

        let bubbleView = UIView()
        bubbleView.layer.cornerRadius = 10
        bubbleView.layer.masksToBounds = true
        bubbleView.autoSetDimensions(to: CGSize(width: 100, height: 30))
        bubbleView.addSubview(chatColorView)
        chatColorView.autoPinEdgesToSuperviewEdges()

        let containerView = UIView()
        containerView.addSubview(bubbleView)
        bubbleView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 8)
        bubbleView.autoPinHeightToSuperview()
        return containerView
    }

    func buildHeaderPreview() -> UIView {
        let vStackView = UIStackView()
        vStackView.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 2)
        vStackView.isLayoutMarginsRelativeArrangement = true
        vStackView.axis = .vertical
        vStackView.autoSetDimension(.height, toSize: 28)
        vStackView.addBackgroundView(withBackgroundColor: Theme.backgroundColor)

        vStackView.addArrangedSubview(.vStretchingSpacer())

        let hStackView = UIStackView()
        hStackView.autoSetDimension(.height, toSize: 14)
        vStackView.addArrangedSubview(hStackView)

        let backImageView = UIImageView()
        backImageView.contentMode = .scaleAspectFit
        backImageView.setTemplateImage(UIImage(imageLiteralResourceName: "NavBarBack"), tintColor: Theme.primaryIconColor)
        backImageView.autoSetDimension(.width, toSize: 10)
        hStackView.addArrangedSubview(backImageView)

        hStackView.addArrangedSubview(.spacer(withWidth: 6))

        let circleView = CircleView(diameter: 14)
        circleView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray05
        hStackView.addArrangedSubview(circleView)

        hStackView.addArrangedSubview(.spacer(withWidth: 4))

        let contactNameLabel = UILabel()
        contactNameLabel.font = .semiboldFont(ofSize: 8)
        contactNameLabel.textColor = Theme.primaryTextColor
        contactNameLabel.text = OWSLocalizedString(
            "WALLPAPER_MINI_PREVIEW_CONTACT_NAME",
            comment: "Placeholder text for header of the wallpaper mini preview"
        )
        hStackView.addArrangedSubview(contactNameLabel)

        hStackView.addArrangedSubview(.hStretchingSpacer())

        let videoCallImageView = UIImageView()
        videoCallImageView.contentMode = .scaleAspectFit
        videoCallImageView.autoSetDimension(.width, toSize: 10)
        videoCallImageView.setTemplateImageName(Theme.iconName(.buttonVideoCall), tintColor: Theme.primaryIconColor)
        hStackView.addArrangedSubview(videoCallImageView)

        hStackView.addArrangedSubview(.spacer(withWidth: 8))

        let audioCallImageView = UIImageView()
        audioCallImageView.contentMode = .scaleAspectFit
        audioCallImageView.autoSetDimension(.width, toSize: 10)
        audioCallImageView.setTemplateImageName(Theme.iconName(.buttonVoiceCall), tintColor: Theme.primaryIconColor)
        hStackView.addArrangedSubview(audioCallImageView)

        return vStackView
    }

    func buildComposerPreview() -> UIView {
        let stackView = UIStackView()
        stackView.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 5)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.autoSetDimension(.height, toSize: 24)
        stackView.addBackgroundView(withBackgroundColor: Theme.backgroundColor)

        let plusImageView = UIImageView()
        plusImageView.contentMode = .scaleAspectFit
        plusImageView.setTemplateImageName("plus", tintColor: Theme.primaryIconColor)
        plusImageView.autoSetDimension(.width, toSize: 10)
        stackView.addArrangedSubview(plusImageView)

        stackView.addArrangedSubview(.spacer(withWidth: 8))

        let pillView = PillView()
        pillView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray05
        stackView.addArrangedSubview(pillView)

        stackView.addArrangedSubview(.spacer(withWidth: 8))

        let cameraImageView = UIImageView()
        cameraImageView.contentMode = .scaleAspectFit
        cameraImageView.autoSetDimension(.width, toSize: 10)
        cameraImageView.setTemplateImageName(Theme.iconName(.buttonCamera), tintColor: Theme.primaryIconColor)
        stackView.addArrangedSubview(cameraImageView)

        stackView.addArrangedSubview(.spacer(withWidth: 8))

        let microphoneImageView = UIImageView()
        microphoneImageView.contentMode = .scaleAspectFit
        microphoneImageView.autoSetDimension(.width, toSize: 10)
        microphoneImageView.setTemplateImageName(Theme.iconName(.buttonMicrophone), tintColor: Theme.primaryIconColor)
        stackView.addArrangedSubview(microphoneImageView)

        return stackView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

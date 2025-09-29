//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
public import SignalUI

final public class ColorAndWallpaperSettingsViewController: OWSTableViewController2 {
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
            selector: #selector(chatColorsDidChange),
            name: ChatColorSettingStore.chatColorsDidChangeNotification,
            object: nil
        )
    }

    private var wallpaperViewBuilder: WallpaperViewBuilder?

    private func updateWallpaperViewBuilder() {
        wallpaperViewBuilder = SSKEnvironment.shared.databaseStorageRef.read { tx in Wallpaper.viewBuilder(for: thread, tx: tx) }
    }

    @objc
    private func wallpaperDidChange(notification: Notification) {
        guard notification.object == nil || (notification.object as? String) == thread?.uniqueId else { return }
        updateWallpaperViewBuilder()
        updateChatColor()
        updateTableContents()
    }

    private var chatColor: ColorOrGradientSetting!

    private func updateChatColor() {
        chatColor = SSKEnvironment.shared.databaseStorageRef.read { tx in
            DependenciesBridge.shared.chatColorSettingStore.resolvedChatColor(for: thread, tx: tx)
        }
    }

    @objc
    private func chatColorsDidChange(_ notification: NSNotification) {
        guard notification.object == nil || (notification.object as? String) == thread?.uniqueId else { return }
        updateChatColor()
        updateTableContents()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("COLOR_AND_WALLPAPER_SETTINGS_TITLE", comment: "Title for the color & wallpaper settings view.")

        updateWallpaperViewBuilder()
        updateChatColor()
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
            let miniPreview = MiniPreviewView(wallpaperViewBuilder: self.wallpaperViewBuilder, chatColor: self.chatColor)
            cell.contentView.addSubview(miniPreview)
            miniPreview.autoPinEdgesToSuperviewEdges()
            return cell
        } actionBlock: {}
        previewSection.add(previewItem)

        contents.add(previewSection)

        do {
            let chatColorSection = OWSTableSection()
            chatColorSection.customHeaderHeight = 14

            let defaultColorView = ColorOrGradientSwatchView(setting: chatColor, shapeMode: .circle)
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
                let viewController = SSKEnvironment.shared.databaseStorageRef.read { tx in
                    ChatColorViewController.load(thread: self.thread, tx: tx)
                }
                self.navigationController?.pushViewController(viewController, animated: true)
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
            withText: OWSLocalizedString(
                "WALLPAPER_SETTINGS_SET_WALLPAPER",
                comment: "Set wallpaper action in wallpaper settings view."
            )
        ) { [weak self] in
            guard let self = self else { return }
            let viewController = SSKEnvironment.shared.databaseStorageRef.read { tx in
                SetWallpaperViewController.load(thread: self.thread, tx: tx)
            }
            self.navigationController?.pushViewController(viewController, animated: true)
        })

        wallpaperSection.add(OWSTableItem.switch(
            withText: OWSLocalizedString("WALLPAPER_SETTINGS_DIM_WALLPAPER",
                                        comment: "Dim wallpaper action in wallpaper settings view."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "dim_wallpaper"),
            isOn: { () -> Bool in
                SSKEnvironment.shared.databaseStorageRef.read {
                    return DependenciesBridge.shared.wallpaperStore.fetchDimInDarkModeForRendering(
                        for: self.thread?.uniqueId,
                        tx: $0
                    )
                }
            },
            isEnabled: {
                SSKEnvironment.shared.databaseStorageRef.read {
                    DependenciesBridge.shared.wallpaperStore.fetchWallpaperForRendering(
                        for: self.thread?.uniqueId,
                        tx: $0
                    ) != nil
                }
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
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
            let wallpaperStore = DependenciesBridge.shared.wallpaperStore
            wallpaperStore.setDimInDarkMode(sender.isOn, for: self.thread?.uniqueId, tx: tx)
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
        Task {
            do {
                let wallpaperStore = DependenciesBridge.shared.wallpaperStore
                let onInsert = { [wallpaperStore] (tx: DBWriteTransaction) throws -> Void in
                    try wallpaperStore.reset(for: thread, tx: tx)
                }

                if let thread {
                    try await DependenciesBridge.shared.wallpaperImageStore.setWallpaperImage(nil, for: thread, onInsert: onInsert)
                } else {
                    try await DependenciesBridge.shared.wallpaperImageStore.setGlobalThreadWallpaperImage(nil, onInsert: onInsert)
                }
            } catch {
                owsFailDebug("Failed to clear wallpaper with error: \(error)")
                await MainActor.run {
                    OWSActionSheets.showErrorAlert(
                        message: OWSLocalizedString("WALLPAPER_SETTINGS_FAILED_TO_CLEAR",
                                                   comment: "An error indicating to the user that we failed to clear the wallpaper.")
                    )
                }
            }
            await MainActor.run {
                self.updateTableContents()
            }
        }
    }

    private func resetAllWallpapers() {
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
            do {
                let wallpaperStore = DependenciesBridge.shared.wallpaperStore
                try wallpaperStore.resetAll(tx: tx)
                try DependenciesBridge.shared.wallpaperImageStore.resetAllWallpaperImages(tx: tx)
            } catch {
                owsFailDebug("Failed to reset all wallpapers with error: \(error)")
                DispatchQueue.main.async {
                    OWSActionSheets.showErrorAlert(
                        message: OWSLocalizedString("WALLPAPER_SETTINGS_FAILED_TO_RESET",
                                                   comment: "An error indicating to the user that we failed to reset all wallpapers.")
                    )
                }
            }
            tx.addSyncCompletion {
                Task { @MainActor in
                    self.updateTableContents()
                }
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
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { [thread] tx in
            DependenciesBridge.shared.chatColorSettingStore.setChatColorSetting(
                .auto,
                for: thread,
                tx: tx
            )
        }
    }

    private func resetAllChatColors() {
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
            DependenciesBridge.shared.chatColorSettingStore.resetAllSettings(tx: tx)
        }
    }
}

// MARK: -

final private class MiniPreviewView: UIView {
    private let hasWallpaper: Bool
    private let chatColor: ColorOrGradientSetting

    init(wallpaperViewBuilder: WallpaperViewBuilder?, chatColor: ColorOrGradientSetting) {
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
        self.chatColor = chatColor

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
        let chatColorView = CVColorOrGradientView()
        chatColorView.configure(value: chatColor.asValue, referenceView: self)

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

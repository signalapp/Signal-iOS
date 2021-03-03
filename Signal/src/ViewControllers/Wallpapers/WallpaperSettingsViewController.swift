//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class WallpaperSettingsViewController: OWSTableViewController2 {
    let thread: TSThread?
    public init(thread: TSThread? = nil) {
        self.thread = thread
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: Wallpaper.wallpaperDidChangeNotification,
            object: nil
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("WALLPAPER_SETTINGS_TITLE", comment: "Title for the wallpaper settings view.")

        updateTableContents()
    }

    @objc
    func updateTableContents() {
        let contents = OWSTableContents()

        let previewSection = OWSTableSection()
        previewSection.hasBackground = false
        previewSection.headerTitle = NSLocalizedString("WALLPAPER_SETTINGS_PREVIEW",
                                                       comment: "Title for the wallpaper settings preview section.")
        let previewItem = OWSTableItem { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            guard let self = self else { return cell }
            let miniPreview = MiniPreviewView(thread: self.thread)
            cell.contentView.addSubview(miniPreview)
            miniPreview.autoPinWidthToSuperview(withMargin: Self.cellHOuterMargin)
            miniPreview.autoPinHeightToSuperview()
            return cell
        } actionBlock: {}
        previewSection.add(previewItem)

        contents.addSection(previewSection)

        let setSection = OWSTableSection()
        setSection.customHeaderHeight = 14

        let setWallpaperItem = OWSTableItem.disclosureItem(
            withText: NSLocalizedString("WALLPAPER_SETTINGS_SET_WALLPAPER",
                                        comment: "Set wallpaper action in wallpaper settings view."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "set_wallpaper")
        ) { [weak self] in
            guard let self = self else { return }
            let vc = SetWallpaperViewController(thread: self.thread)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        setSection.add(setWallpaperItem)

        let dimWallpaperItem = OWSTableItem.switch(
            withText: NSLocalizedString("WALLPAPER_SETTINGS_DIM_WALLPAPER",
                                        comment: "Dim wallpaper action in wallpaper settings view."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "dim_wallpaper"),
            isOn: { () -> Bool in
                self.databaseStorage.read { Wallpaper.dimInDarkMode(for: self.thread, transaction: $0) }
            },
            isEnabledBlock: {
                self.databaseStorage.read { Wallpaper.exists(for: self.thread, transaction: $0) }
            },
            target: self,
            selector: #selector(updateWallpaperDimming)
        )
        setSection.add(dimWallpaperItem)

        contents.addSection(setSection)

        let resetSection = OWSTableSection()
        resetSection.customHeaderHeight = 14

        let clearWallpaperItem = OWSTableItem.actionItem(
            name: NSLocalizedString("WALLPAPER_SETTINGS_CLEAR_WALLPAPER",
                                    comment: "Clear wallpaper action in wallpaper settings view."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "clear_wallpaper")
        ) { [weak self] in
            self?.didPressClearWallpaper()
        }
        resetSection.add(clearWallpaperItem)

        if thread == nil {
            let resetAllWallpapersItem = OWSTableItem.actionItem(
                name: NSLocalizedString("WALLPAPER_SETTINGS_RESET_ALL",
                                        comment: "Reset all wallpapers action in wallpaper settings view."),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "reset_all_wallpapers")
            ) { [weak self] in
                self?.didPressResetAllWallpapers()
            }
            resetSection.add(resetAllWallpapersItem)
        }

        contents.addSection(resetSection)

        self.contents = contents
    }

    @objc
    func updateWallpaperDimming(_ sender: UISwitch) {
        databaseStorage.asyncWrite { transaction in
            do {
                try Wallpaper.setDimInDarkMode(sender.isOn, for: self.thread, transaction: transaction)
            } catch {
                owsFailDebug("Failed to set dim in dark mode \(error)")
            }
        }
    }

    func didPressClearWallpaper() {
        let title: String
        if thread != nil {
            title = NSLocalizedString(
                "WALLPAPER_SETTINGS_CLEAR_WALLPAPER_CHAT_CONFIRMATION",
                comment: "Confirmation dialog when clearing the wallpaper for a specific chat."
            )
        } else {
            title = NSLocalizedString(
                "WALLPAPER_SETTINGS_CLEAR_WALLPAPER_GLOBAL_CONFIRMATION",
                comment: "Confirmation dialog when clearing the global wallpaper."
            )
        }

        OWSActionSheets.showConfirmationAlert(
            title: title,
            proceedTitle: NSLocalizedString(
                "WALLPAPER_SETTINGS_CLEAR_WALLPAPER",
                comment: "Clear wallpaper action in wallpaper settings view."
            ),
            proceedStyle: .destructive
        ) { _ in
            self.clearWallpaper()
        }
    }

    func clearWallpaper() {
        databaseStorage.asyncWrite { transaction in
            do {
                try Wallpaper.clear(for: self.thread, transaction: transaction)
            } catch {
                owsFailDebug("Failed to clear wallpaper with error: \(error)")
                DispatchQueue.main.async {
                    OWSActionSheets.showErrorAlert(
                        message: NSLocalizedString("WALLPAPER_SETTINGS_FAILED_TO_CLEAR",
                                                   comment: "An error indicating to the user that we failed to clear the wallpaper.")
                    )
                }
            }
        }
    }

    func didPressResetAllWallpapers() {
        OWSActionSheets.showConfirmationAlert(
            title: NSLocalizedString(
                "WALLPAPER_SETTINGS_RESET_ALL_WALLPAPERS_CONFIRMATION",
                comment: "Confirmation dialog when resetting all wallpapers."
            ),
            proceedTitle: NSLocalizedString(
                "WALLPAPER_SETTINGS_RESET_ALL",
                comment: "Reset all wallpapers action in wallpaper settings view."
            ),
            proceedStyle: .destructive
        ) { _ in
            self.resetAllWallpapers()
        }
    }

    func resetAllWallpapers() {
        databaseStorage.asyncWrite { transaction in
            do {
                try Wallpaper.resetAll(transaction: transaction)
            } catch {
                owsFailDebug("Failed to reset all wallpapers with error: \(error)")
                DispatchQueue.main.async {
                    OWSActionSheets.showErrorAlert(
                        message: NSLocalizedString("WALLPAPER_SETTINGS_FAILED_TO_RESET",
                                                   comment: "An error indicating to the user that we failed to reset all wallpapers.")
                    )
                }
            }
        }
    }
}

class MiniPreviewView: UIView {
    init(thread: TSThread?) {
        super.init(frame: .zero)

        layer.cornerRadius = OWSTableViewController2.cellRounding
        backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray05

        let stackViewContainer: UIView
        if let wallpaperView = databaseStorage.read(
            block: { Wallpaper.view(for: thread, transaction: $0) }
        ) {
            stackViewContainer = wallpaperView
        } else {
            stackViewContainer = UIView()
            stackViewContainer.backgroundColor = Theme.backgroundColor
        }

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
        bubbleView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray95 : .ows_white
        containerView.addSubview(bubbleView)
        bubbleView.autoPinEdge(toSuperviewEdge: .leading, withInset: 8)
        bubbleView.autoPinHeightToSuperview()
        return containerView
    }

    func buildOutgoingBubble() -> UIView {
        let containerView = UIView()
        let bubbleView = UIView()
        bubbleView.layer.cornerRadius = 10
        bubbleView.autoSetDimensions(to: CGSize(width: 100, height: 30))
        bubbleView.backgroundColor = .ows_accentBlue
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

        let backImage = CurrentAppContext().isRTL ? #imageLiteral(resourceName: "NavBarBackRTL") : #imageLiteral(resourceName: "NavBarBack")

        let backImageView = UIImageView()
        backImageView.contentMode = .scaleAspectFit
        backImageView.setTemplateImage(backImage, tintColor: Theme.primaryIconColor)
        backImageView.autoSetDimension(.width, toSize: 10)
        hStackView.addArrangedSubview(backImageView)

        hStackView.addArrangedSubview(.spacer(withWidth: 6))

        let circleView = CircleView(diameter: 14)
        circleView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray05
        hStackView.addArrangedSubview(circleView)

        hStackView.addArrangedSubview(.spacer(withWidth: 4))

        let contactNameLabel = UILabel()
        contactNameLabel.font = .ows_semiboldFont(withSize: 8)
        contactNameLabel.textColor = Theme.primaryTextColor
        contactNameLabel.text = NSLocalizedString(
            "WALLPAPER_MINI_PREVIEW_CONTACT_NAME",
            comment: "Placeholder text for header of the wallpaper mini preview"
        )
        hStackView.addArrangedSubview(contactNameLabel)

        hStackView.addArrangedSubview(.hStretchingSpacer())

        let videoCallImageView = UIImageView()
        videoCallImageView.contentMode = .scaleAspectFit
        videoCallImageView.autoSetDimension(.width, toSize: 10)
        videoCallImageView.setTemplateImageName(Theme.iconName(.videoCall), tintColor: Theme.primaryIconColor)
        hStackView.addArrangedSubview(videoCallImageView)

        hStackView.addArrangedSubview(.spacer(withWidth: 8))

        let audioCallImageView = UIImageView()
        audioCallImageView.contentMode = .scaleAspectFit
        audioCallImageView.autoSetDimension(.width, toSize: 10)
        audioCallImageView.setTemplateImageName(Theme.iconName(.audioCall), tintColor: Theme.primaryIconColor)
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
        plusImageView.setTemplateImageName("plus-24", tintColor: Theme.primaryIconColor)
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
        cameraImageView.setTemplateImageName(Theme.iconName(.cameraButton), tintColor: Theme.primaryIconColor)
        stackView.addArrangedSubview(cameraImageView)

        stackView.addArrangedSubview(.spacer(withWidth: 8))

        let microphoneImageView = UIImageView()
        microphoneImageView.contentMode = .scaleAspectFit
        microphoneImageView.autoSetDimension(.width, toSize: 10)
        microphoneImageView.setTemplateImageName(Theme.iconName(.micButton), tintColor: Theme.primaryIconColor)
        stackView.addArrangedSubview(microphoneImageView)

        return stackView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

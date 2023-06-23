//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreServices
import SignalMessaging
import SignalUI

class AvatarSettingsViewController: OWSTableViewController2 {
    let context: AvatarContext

    static let headerAvatarSize: CGFloat = UIDevice.current.isIPhone5OrShorter ? 120 : 160

    enum State: Equatable {
        case original(UIImage?)
        case new(AvatarModel?)

        var isNew: Bool {
            guard case .new = self else { return false }
            return true
        }
    }
    private var state: State {
        didSet {
            guard state != oldValue else { return }
            updateHeaderView()
            updateNavigation()
        }
    }

    private var selectedAvatarModel: AvatarModel? {
        guard case .new(let model) = state else { return nil }
        return model
    }

    private lazy var defaultAvatarImage: UIImage? = {
        switch context {
        case .groupId(let groupId):
            return avatarBuilder.avatarImage(forGroupId: groupId, diameterPoints: UInt(Self.headerAvatarSize))
        case .profile:
            return databaseStorage.read { transaction in
                avatarBuilder.defaultAvatarImageForLocalUser(diameterPoints: UInt(Self.headerAvatarSize), transaction: transaction)
            }
        }
    }()

    private let avatarChangeCallback: (UIImage?) -> Void

    init(context: AvatarContext, currentAvatarImage: UIImage?, avatarChangeCallback: @escaping (UIImage?) -> Void) {
        self.context = context
        self.state = .original(currentAvatarImage)
        self.avatarChangeCallback = avatarChangeCallback
        super.init()
        createTopHeader()

        // We only support portrait on non-iPad devices, but if we're
        // already in landscape we need to force the device to rotate.
        // TODO: There might be a better spot to do this, but generally
        // this should never be initialized unless about to be shown.
        if !UIDevice.current.isIPad { UIDevice.current.ows_setOrientation(.portrait) }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        updateTableContents()
        updateNavigation()
    }

    override func themeDidChange() {
        super.themeDidChange()

        updateHeaderViewLayout(forceUpdate: true)
        optionViews.removeAll()
        updateTableContents()
    }

    @objc
    private func didTapCancel() {
        guard state.isNew else { return dismiss(animated: true) }
        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            self?.dismiss(animated: true)
        })
    }

    @objc
    private func didTapDone() {
        defer { dismiss(animated: true) }

        guard case .new(let model) = state else {
            return owsFailDebug("Tried to tap done in unexpected state")
        }

        if let model = model {
            databaseStorage.asyncWrite { [context] transaction in
                Self.avatarHistoryManager.touchedModel(model, in: context, transaction: transaction)
            }
            guard let newAvatar = avatarBuilder.avatarImage(
                model: model,
                diameterPixels: kOWSProfileManager_MaxAvatarDiameterPixels
            ) else {
                owsFailDebug("Failed to generate new avatar.")
                return
            }
            avatarChangeCallback(newAvatar)
        } else {
            // Avatar was cleared.
            avatarChangeCallback(nil)
        }
    }

    private let headerImageView = AvatarImageView()
    private let topHeaderStack = UIStackView()
    private func createTopHeader() {
        topHeaderStack.isLayoutMarginsRelativeArrangement = true
        topHeaderStack.axis = .vertical
        topHeaderStack.alignment = .center
        topHeaderStack.spacing = 24

        headerImageView.autoSetDimensions(to: CGSize(square: Self.headerAvatarSize))
        topHeaderStack.addArrangedSubview(headerImageView)

        headerButtonStack.axis = .vertical
        headerButtonStack.alignment = .center
        headerButtonStack.spacing = 8
        topHeaderStack.addArrangedSubview(headerButtonStack)

        createClearButton()

        topHeader = topHeaderStack

        updateHeaderView()
    }

    private lazy var clearButton = UIView()
    private let xImageView = UIImageView()
    private func createClearButton() {
        clearButton.autoSetDimensions(to: CGSize.square(32))
        clearButton.layer.cornerRadius = 16

        clearButton.layer.shadowColor = UIColor.black.cgColor
        clearButton.layer.shadowOpacity = 0.2
        clearButton.layer.shadowRadius = 4
        clearButton.layer.shadowOffset = CGSize(width: 0, height: 2)

        let secondaryShadowView = UIView()
        secondaryShadowView.layer.shadowColor = UIColor.black.cgColor
        secondaryShadowView.layer.shadowOpacity = 0.12
        secondaryShadowView.layer.shadowRadius = 16
        secondaryShadowView.layer.shadowOffset = CGSize(width: 0, height: 4)

        clearButton.addSubview(secondaryShadowView)
        secondaryShadowView.autoPinEdgesToSuperviewEdges()

        xImageView.image = UIImage(imageLiteralResourceName: "x-20")
        xImageView.autoSetDimensions(to: CGSize.square(20))
        xImageView.contentMode = .scaleAspectFit

        clearButton.addSubview(xImageView)
        xImageView.autoCenterInSuperview()

        topHeaderStack.addSubview(clearButton)
        clearButton.autoPinEdge(.trailing, to: .trailing, of: headerImageView, withOffset: -8)
        clearButton.autoPinEdge(.top, to: .top, of: headerImageView, withOffset: 8)

        clearButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapClear)))
    }

    @objc
    private func didTapClear() {
        state = .new(nil)
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let section = OWSTableSection()
        section.headerTitle = OWSLocalizedString(
            "AVATAR_SETTINGS_VIEW_SELECT_AN_AVATAR",
            comment: "Title for the previously used and preset avatar section."
        )
        section.add(.init { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self = self else { return cell }
            cell.selectionStyle = .none
            self.configureAvatarsCell(cell)
            return cell
        } actionBlock: {})
        contents.add(section)
    }

    private func updateNavigation() {
        navigationItem.leftBarButtonItem = .init(barButtonSystemItem: .cancel, target: self, action: #selector(didTapCancel))

        if state.isNew {
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

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate { [weak self] _ in
            self?.updateHeaderViewLayout()
        } completion: { [weak self] _ in
            self?.updateHeaderViewLayout()
        }
    }

    // MARK: - Avatar Options

    private var optionViews = [OptionView]()
    private func reusableOptionView(for index: Int) -> OptionView {
        guard let optionView = optionViews[safe: index] else {
            while optionViews.count <= index {
                let optionView = OptionView(delegate: self)
                optionViews.append(optionView)
            }
            return reusableOptionView(for: index)
        }
        return optionView
    }

    private func configureAvatarsCell(_ cell: UITableViewCell) {
        let rowWidth = max(0, view.width - (view.safeAreaInsets.totalWidth + cellOuterInsets.totalWidth + Self.cellHInnerMargin * 2))
        let avatarSpacing: CGFloat = 16
        let minAvatarSize: CGFloat = min(66, (rowWidth - (avatarSpacing * 3)) / 4)
        let avatarsPerRow = max(1, Int(floor(rowWidth + avatarSpacing) / (minAvatarSize + avatarSpacing)))
        let avatarSize = max(minAvatarSize, (rowWidth - (avatarSpacing * CGFloat(avatarsPerRow - 1))) / CGFloat(avatarsPerRow))

        let vStackView = UIStackView()
        vStackView.axis = .vertical
        vStackView.spacing = avatarSpacing
        vStackView.alignment = .leading
        cell.contentView.addSubview(vStackView)
        vStackView.autoPinEdgesToSuperviewMargins()

        let avatars: [(model: AvatarModel, image: UIImage)] = databaseStorage.read { transaction in
            let models = Self.avatarHistoryManager.models(for: context, transaction: transaction)
            return models.compactMap { model in
                guard let image = avatarBuilder.avatarImage(
                    model: model,
                    diameterPoints: UInt(avatarSize)
                ) else {
                    owsFailDebug("Failed to prepare avatar for model \(model.identifier).")
                    return nil
                }
                return (model, image)
            }
        }

        for (row, avatars) in avatars.chunked(by: avatarsPerRow).enumerated() {
            let hStackView = UIStackView()
            hStackView.axis = .horizontal
            hStackView.spacing = avatarSpacing
            vStackView.addArrangedSubview(hStackView)

            for (index, avatar) in avatars.enumerated() {
                let view = reusableOptionView(for: (row * avatarsPerRow) + index)
                view.autoSetDimensions(to: CGSize(square: avatarSize))
                view.configure(model: avatar.model, image: avatar.image, isSelected: avatar.model == selectedAvatarModel)
                hStackView.addArrangedSubview(view)
            }
        }
    }

    // MARK: - Header

    func updateHeaderView() {
        switch state {
        case .new(let model):
            if let model = model {
                clearButton.isHidden = false
                headerImageView.image = avatarBuilder.avatarImage(model: model, diameterPoints: UInt(Self.headerAvatarSize))
            } else {
                clearButton.isHidden = true
                headerImageView.image = defaultAvatarImage
            }
        case .original(let image):
            if let image = image {
                clearButton.isHidden = false
                headerImageView.image = image
            } else {
                clearButton.isHidden = true
                headerImageView.image = defaultAvatarImage
            }
        }

        updateHeaderViewLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateHeaderViewLayout()
    }

    private var previousSizeReference: CGFloat?
    private func updateHeaderViewLayout(forceUpdate: Bool = false) {
        // Update button layout only when the view size changes.
        guard view.width != previousSizeReference || forceUpdate else { return }
        previousSizeReference = view.width

        topHeaderStack.layoutMargins = cellOuterInsetsWithMargin(top: 24, bottom: 13)

        updateHeaderButtons()
    }

    // MARK: - Header Buttons
    private let headerButtonStack = UIStackView()

    private func buildHeaderButtons() -> [UIView] {
        return [
            buildHeaderButton(
                icon: .buttonCamera,
                text: OWSLocalizedString(
                    "AVATAR_SETTINGS_VIEW_CAMERA_BUTTON",
                    comment: "Text indicating the user can select an avatar from their camera"
                ),
                action: { [weak self] in
                    guard let self = self else { return }
                    self.ows_askForCameraPermissions { granted in
                        guard granted else { return }
                        let picker = OWSImagePickerController()
                        picker.delegate = self
                        picker.allowsEditing = false
                        picker.sourceType = .camera
                        picker.mediaTypes = [kUTTypeImage as String]
                        self.present(picker, animated: true)
                    }
                }
            ),
            buildHeaderButton(
                icon: .buttonPhotoLibrary,
                text: OWSLocalizedString(
                    "AVATAR_SETTINGS_VIEW_PHOTO_BUTTON",
                    comment: "Text indicating the user can select an avatar from their photos"
                ),
                action: { [weak self] in
                    guard let self = self else { return }
                    self.ows_askForMediaLibraryPermissions { granted in
                        guard granted else { return }
                        let picker = OWSImagePickerController()
                        picker.delegate = self
                        picker.sourceType = .photoLibrary
                        picker.mediaTypes = [kUTTypeImage as String]
                        self.present(picker, animated: true)
                    }
                }
            ),
            buildHeaderButton(
                icon: .buttonText,
                text: OWSLocalizedString(
                    "AVATAR_SETTINGS_VIEW_TEXT_BUTTON",
                    comment: "Text indicating the user can create a new avatar with text"
                ),
                action: { [weak self] in
                    let model = AvatarModel(type: .text(""), theme: .default)
                    let vc = AvatarEditViewController(model: model) { [weak self] editedModel in
                        self?.databaseStorage.asyncWrite { transaction in
                            guard let self = self else { return }
                            self.avatarHistoryManager.touchedModel(
                                editedModel,
                                in: self.context,
                                transaction: transaction
                            )
                        } completion: {
                            self?.state = .new(editedModel)
                            self?.updateTableContents()
                        }
                    }
                    self?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
                }
            )
        ]
    }

    private func updateHeaderButtons() {
        clearButton.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray15 : UIColor(rgbHex: 0xf8f9f9)
        xImageView.tintColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_black

        headerButtonStack.removeAllSubviews()
        let headerButtons = buildHeaderButtons()

        let spacerWidth: CGFloat = 8
        let totalSpacerWidth = CGFloat(headerButtons.count - 1) * spacerWidth
        let maxAvailableButtonWidth = view.width - (cellOuterInsets.totalWidth + totalSpacerWidth)
        let minButtonWidth = maxAvailableButtonWidth / 4

        var buttonWidth = max(maxIconButtonWidth, minButtonWidth)
        let needsTwoRows = buttonWidth * CGFloat(headerButtons.count) > maxAvailableButtonWidth
        if needsTwoRows { buttonWidth *= 2 }
        headerButtons.forEach { $0.autoSetDimension(.width, toSize: buttonWidth) }

        func addButtonRow(_ buttons: [UIView]) {
            let stackView = UIStackView()
            stackView.axis = .horizontal
            stackView.distribution = .fillEqually
            stackView.spacing = spacerWidth
            buttons.forEach { stackView.addArrangedSubview($0) }
            headerButtonStack.addArrangedSubview(stackView)
        }

        if needsTwoRows {
            addButtonRow(Array(headerButtons.prefix(Int(ceil(CGFloat(headerButtons.count) / 2)))))
            addButtonRow(headerButtons.suffix(Int(floor(CGFloat(headerButtons.count) / 2))))
        } else {
            addButtonRow(headerButtons)
        }
    }

    private var maxIconButtonWidth: CGFloat = 0
    private func buildHeaderButton(icon: ThemeIcon, text: String, isEnabled: Bool = true, action: @escaping () -> Void) -> UIView {

        let button = SettingsHeaderButton(
            text: text,
            icon: icon,
            backgroundColor: Self.cellBackgroundColor(isUsingPresentedStyle: true),
            isEnabled: isEnabled,
            block: action
        )

        if maxIconButtonWidth < button.minimumWidth {
            maxIconButtonWidth = button.minimumWidth
        }

        return button
    }
}

extension AvatarSettingsViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true, completion: nil)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let originalImage = info[.originalImage] as? UIImage else {
            return owsFailDebug("Failed to pick image")
        }

        dismiss(animated: true) { [weak self] in
            let vc = CropScaleImageViewController(srcImage: originalImage) { croppedImage in
                guard let self = self else { return }
                let imageModel = self.databaseStorage.write { transaction in
                    self.avatarHistoryManager.recordModelForImage(
                        croppedImage,
                        in: self.context,
                        transaction: transaction
                    )
                }
                DispatchQueue.main.async {
                    self.state = .new(imageModel)
                    self.updateTableContents()
                }
            }
            self?.present(vc, animated: true)
        }
    }
}

extension AvatarSettingsViewController: OptionViewDelegate {
    fileprivate func didSelectOptionView(_ optionView: OptionView, model: AvatarModel) {
        optionViews.forEach { $0.isSelected = $0 == optionView }
        state = .new(model)
    }

    fileprivate func didEditOptionView(_ optionView: OptionView, model: AvatarModel) {
        owsAssertDebug(model.type.isEditable)

        let vc = AvatarEditViewController(model: model) { [weak self, context] editedModel in
            self?.databaseStorage.asyncWrite { transaction in
                Self.avatarHistoryManager.touchedModel(
                    editedModel,
                    in: context,
                    transaction: transaction
                )
            } completion: {
                self?.state = .new(editedModel)
                self?.updateTableContents()
            }
        }
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    fileprivate func didDeleteOptionView(_ optionView: OptionView, model: AvatarModel) {
        owsAssertDebug(model.type.isDeletable)
        databaseStorage.asyncWrite { [context] transaction in
            Self.avatarHistoryManager.deletedModel(
                model,
                in: context,
                transaction: transaction
            )
        } completion: { [weak self] in
            // If we just deleted the selected avatar, also clear it.
            if self?.selectedAvatarModel == model {
                self?.state = .new(nil)
            }
            self?.updateTableContents()
        }
    }
}

private protocol OptionViewDelegate: AnyObject {
    func didSelectOptionView(_ optionView: OptionView, model: AvatarModel)
    func didEditOptionView(_ optionView: OptionView, model: AvatarModel)
    func didDeleteOptionView(_ optionView: OptionView, model: AvatarModel)
}

private class OptionView: UIView {
    private let imageView = AvatarImageView()
    private var imageViewInsetConstraints: [NSLayoutConstraint]?
    private let editOverlayView = AvatarImageView()

    private weak var delegate: (OptionViewDelegate & UIViewController)?

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            updateSelectionState()
        }
    }

    init(delegate: OptionViewDelegate & UIViewController) {
        self.delegate = delegate

        super.init(frame: .zero)

        addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges()
        updateSelectionState()

        editOverlayView.image = UIImage(imageLiteralResourceName: "edit-fill")
        editOverlayView.backgroundColor = .ows_blackAlpha20
        editOverlayView.tintColor = .white
        editOverlayView.contentMode = .center
        imageView.addSubview(editOverlayView)
        editOverlayView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(margin: 2.5))
        editOverlayView.layer.borderWidth = 1.5
        editOverlayView.isHidden = true

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = width / 2
        layer.masksToBounds = true
    }

    @objc
    private func handleTap() {
        guard let model = model else {
            return owsFailDebug("Unexpectedly missing model in OptionView")
        }

        if !isSelected {
            isSelected = true
            delegate?.didSelectOptionView(self, model: model)
        } else if model.type.isEditable {
            delegate?.didEditOptionView(self, model: model)
        }
    }

    @objc
    private func handleLongPress() {
        guard let model = model else {
            return owsFailDebug("Unexpectedly missing model in OptionView")
        }

        let actionSheet = ActionSheetController()
        actionSheet.addAction(OWSActionSheets.cancelAction)
        if model.type.isEditable {
            actionSheet.addAction(.init(title: CommonStrings.editButton, handler: { [weak self] _ in
                guard let self = self else { return }
                self.delegate?.didEditOptionView(self, model: model)
            }))
        }
        if model.type.isDeletable {
            actionSheet.addAction(.init(title: CommonStrings.deleteButton, handler: { [weak self] _ in
                guard let self = self else { return }
                self.delegate?.didDeleteOptionView(self, model: model)
            }))
        }
        delegate?.presentActionSheet(actionSheet)
    }

    func updateSelectionState() {
        if isSelected {
            layer.borderColor = Theme.primaryTextColor.cgColor
            layer.borderWidth = 2.5
        } else {
            layer.borderColor = nil
            layer.borderWidth = 0
        }

        editOverlayView.isHidden = true
        editOverlayView.layer.borderColor = OWSTableViewController2.cellBackgroundColor(isUsingPresentedStyle: true).cgColor

        guard let model = model else { return }

        if model.type.isEditable {
            editOverlayView.isHidden = !isSelected
        }
    }

    private var model: AvatarModel?
    func configure(model: AvatarModel, image: UIImage, isSelected: Bool) {
        self.model = model
        self.isSelected = isSelected
        imageView.image = image
    }
}

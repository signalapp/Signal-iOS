//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class AvatarEditViewController: OWSTableViewController2 {
    private let originalModel: AvatarModel
    private var model: AvatarModel {
        didSet {
            updateHeaderView()
            updateNavigation()
        }
    }
    private let completion: (AvatarModel) -> Void

    static let headerAvatarSize: CGFloat = UIDevice.current.isIPhone5OrShorter ? 120 : 160

    init(model: AvatarModel, completion: @escaping (AvatarModel) -> Void) {
        self.originalModel = model
        self.model = model
        self.completion = completion
        super.init()
        createTopHeader()
        createBottomFooter()
        shouldAvoidKeyboard = true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        updateNavigation()
        updateHeaderView()
        updateFooterView()
    }

    override func themeDidChange() {
        super.themeDidChange()

        optionViews.removeAll()
        updateFooterViewLayout(forceUpdate: true)
    }

    @objc
    func didTapCancel() {
        guard model != originalModel else { return dismiss(animated: true) }
        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            self?.dismiss(animated: true)
        })
    }

    @objc
    func didTapDone() {
        defer { dismiss(animated: true) }

        guard model != originalModel else {
            return owsFailDebug("Tried to tap done in unexpected state")
        }

        completion(model)
    }

    private func updateNavigation() {
        navigationItem.leftBarButtonItem = .init(barButtonSystemItem: .cancel, target: self, action: #selector(didTapCancel))

        if case .text(let text) = model.type, text.nilIfEmpty == nil {
            navigationItem.rightBarButtonItem = nil
        } else if model != originalModel {
            navigationItem.rightBarButtonItem = .init(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate { [weak self] _ in
            self?.updateHeaderView()
            self?.updateFooterViewLayout()
        } completion: { [weak self] _ in
            self?.updateHeaderView()
            self?.updateFooterViewLayout()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard case .text(let text) = model.type, text.isEmpty else { return }
        headerTextField.becomeFirstResponder()
    }

    // MARK: - Segmented Control

    private enum Segments: Int {
        case text, color
    }
    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl()

        control.insertSegment(
            withTitle: NSLocalizedString(
                "AVATAR_EDIT_VIEW_TEXT_SEGMENT",
                comment: "Segment indicating the user can edit the text of the avatar"
            ),
            at: Segments.text.rawValue,
            animated: false
        )
        control.insertSegment(
            withTitle: NSLocalizedString(
                "AVATAR_EDIT_VIEW_COLOR_SEGMENT",
                comment: "Segment indicating the user can edit the color of the avatar"
            ),
            at: Segments.color.rawValue,
            animated: false
        )

        control.selectedSegmentIndex = Segments.color.rawValue

        control.addTarget(
            self,
            action: #selector(segmentedControlDidChange),
            for: .valueChanged
        )

        return control
    }()

    @objc
    func segmentedControlDidChange() {
        guard let selectedSegment = Segments(rawValue: segmentedControl.selectedSegmentIndex) else { return }
        switch selectedSegment {
        case .color:
            headerTextField.resignFirstResponder()
            updateFooterView()
        case .text:
            headerTextField.becomeFirstResponder()
            updateFooterView()
        }
    }

    // MARK: - Header

    private let headerImageView = AvatarImageView()
    private let headerTextField = UITextField()
    private let topHeaderStack = UIStackView()
    private func createTopHeader() {
        topHeaderStack.isLayoutMarginsRelativeArrangement = true
        topHeaderStack.axis = .vertical
        topHeaderStack.alignment = .center

        let topSpacer = UIView.vStretchingSpacer()
        topHeaderStack.addArrangedSubview(topSpacer)

        headerTextField.adjustsFontSizeToFitWidth = true
        headerTextField.textAlignment = .center
        headerTextField.delegate = self
        headerTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        headerTextField.returnKeyType = .done
        headerTextField.autocorrectionType = .no
        headerTextField.spellCheckingType = .no
        headerImageView.addSubview(headerTextField)
        headerTextField.autoPinEdgesToSuperviewEdges(with: AvatarBuilder.avatarTextMargins(diameter: Self.headerAvatarSize))
        headerTextField.isHidden = true

        headerImageView.autoSetDimensions(to: CGSize(square: Self.headerAvatarSize))
        headerImageView.isUserInteractionEnabled = true
        topHeaderStack.addArrangedSubview(headerImageView)

        let bottomSpacer = UIView.vStretchingSpacer()
        topHeaderStack.addArrangedSubview(bottomSpacer)
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
        topSpacer.autoSetDimension(.height, toSize: 16, relation: .greaterThanOrEqual)
        topSpacer.setCompressionResistanceLow()
        bottomSpacer.setCompressionResistanceLow()

        topHeader = topHeaderStack
    }

    func updateHeaderView() {
        topHeaderStack.layoutMargins = cellOuterInsets

        switch model.type {
        case .icon:
            headerTextField.isHidden = true
            headerImageView.image = avatarBuilder.avatarImage(model: model, diameterPoints: UInt(Self.headerAvatarSize))
        case .text(let text):
            headerTextField.isHidden = false
            headerTextField.textColor = model.theme.foregroundColor
            headerTextField.font = AvatarBuilder.avatarMaxFont(
                diameter: Self.headerAvatarSize,
                isEmojiOnly: text.containsOnlyEmoji
            )
            if !headerTextField.isFirstResponder { headerTextField.text = text }
            headerImageView.image = .init(color: model.theme.backgroundColor)
        case .image:
            owsFailDebug("Unexpectedly encountered image model")
        }
    }

    // MARK: - Footer View

    private let bottomFooterStack = UIStackView()
    private let segmentedControlContainer = UIView()
    private let themePickerContainer = UIView()
    private let themeHeaderContainer = UIView()

    private func createBottomFooter() {
        bottomFooterStack.isLayoutMarginsRelativeArrangement = true
        bottomFooterStack.axis = .vertical
        bottomFooterStack.spacing = 16

        segmentedControlContainer.addSubview(segmentedControl)
        segmentedControl.autoPinEdgesToSuperviewEdges()
        bottomFooterStack.addArrangedSubview(segmentedControlContainer)

        bottomFooterStack.addArrangedSubview(themeHeaderContainer)
        bottomFooterStack.addArrangedSubview(themePickerContainer)
        bottomFooterStack.addArrangedSubview(.vStretchingSpacer())

        bottomFooter = bottomFooterStack
    }

    private func updateFooterView() {

        if case .text = model.type {
            segmentedControlContainer.isHiddenInStackView = false
            themeHeaderContainer.isHiddenInStackView = true
            themePickerContainer.isHiddenInStackView = segmentedControl.selectedSegmentIndex == Segments.text.rawValue
        } else {
            segmentedControlContainer.isHiddenInStackView = true
            themeHeaderContainer.isHiddenInStackView = false
            themePickerContainer.isHiddenInStackView = false
        }

        updateFooterViewLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateFooterViewLayout()
    }

    private var previousSizeReference: CGFloat?
    private func updateFooterViewLayout(forceUpdate: Bool = false) {
        // Update theme options layout only when the view size changes.
        guard view.width != previousSizeReference || forceUpdate else { return }
        previousSizeReference = view.width

        segmentedControlContainer.layoutMargins = cellOuterInsetsWithMargin(top: 12, bottom: 10)
        bottomFooterStack.layoutMargins = cellOuterInsets

        updateThemeHeaderContainer()
        updateThemePickerContainer()
    }

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

    private func updateThemeHeaderContainer() {
        themeHeaderContainer.removeAllSubviews()

        let label = UILabel()
        label.text = NSLocalizedString(
            "AVATAR_EDIT_VIEW_CHOOSE_A_COLOR",
            comment: "Text prompting the user to choose a color when editing their avatar"
        )
        label.textColor = Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_gray90
        label.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        themeHeaderContainer.addSubview(label)
        label.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(hMargin: Self.cellHInnerMargin * 0.5, vMargin: 0))
    }

    private func updateThemePickerContainer() {
        themePickerContainer.removeAllSubviews()
        themePickerContainer.layoutMargins = UIEdgeInsets(hMargin: Self.cellHInnerMargin, vMargin: Self.cellVInnerMargin)
        themePickerContainer.backgroundColor = cellBackgroundColor
        themePickerContainer.layer.cornerRadius = Self.cellRounding

        let rowWidth = max(0, view.width - (view.safeAreaInsets.totalWidth + cellOuterInsets.totalWidth + Self.cellHInnerMargin * 2))
        let themeSpacing: CGFloat = 16
        let minThemeSize: CGFloat = min(66, (rowWidth - (themeSpacing * 3)) / 4)
        let themesPerRow = max(1, Int(floor(rowWidth + themeSpacing) / (minThemeSize + themeSpacing)))
        let themeSize = max(minThemeSize, (rowWidth - (themeSpacing * CGFloat(themesPerRow - 1))) / CGFloat(themesPerRow))

        let vStackView = UIStackView()
        vStackView.axis = .vertical
        vStackView.spacing = themeSpacing
        vStackView.alignment = .leading
        themePickerContainer.addSubview(vStackView)
        vStackView.autoPinEdgesToSuperviewMargins()

        for (row, themes) in AvatarTheme.allCases.chunked(by: themesPerRow).enumerated() {
            let hStackView = UIStackView()
            hStackView.axis = .horizontal
            hStackView.spacing = themeSpacing
            vStackView.addArrangedSubview(hStackView)

            for (index, theme) in themes.enumerated() {
                let view = reusableOptionView(for: (row * themesPerRow) + index)
                view.autoSetDimensions(to: CGSize(square: themeSize))
                view.configure(theme: theme, isSelected: model.theme == theme)
                hStackView.addArrangedSubview(view)
            }
        }
    }
}

extension AvatarEditViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string,
            maxGlyphCount: 3
        )
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        updateFooterView()
        return false
    }

    @objc
    func textFieldDidChange() {
        guard case .text = model.type else { return }
        model.type = .text(headerTextField.text ?? "")
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        segmentedControl.selectedSegmentIndex = Segments.text.rawValue
        updateFooterView()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        segmentedControl.selectedSegmentIndex = Segments.color.rawValue
        updateFooterView()
    }
}

extension AvatarEditViewController: OptionViewDelegate {
    fileprivate func didSelectOptionView(_ optionView: OptionView, theme: AvatarTheme) {
        optionViews.forEach { $0.isSelected = $0 == optionView }
        model.theme = theme
    }
}

private protocol OptionViewDelegate: AnyObject {
    func didSelectOptionView(_ optionView: OptionView, theme: AvatarTheme)
}

private class OptionView: UIView {
    private weak var delegate: OptionViewDelegate?
    private let colorView = UIView()
    private var colorViewInsetConstraints: [NSLayoutConstraint]?

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            updateSelectionState()
        }
    }

    init(delegate: OptionViewDelegate) {
        self.delegate = delegate

        super.init(frame: .zero)

        addSubview(colorView)
        updateSelectionState()

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = width / 2
        colorView.layer.cornerRadius = colorView.width / 2
    }

    @objc
    func handleTap() {
        guard let theme = theme else {
            return owsFailDebug("Unexpectedly missing theme in OptionView")
        }

        if !isSelected {
            isSelected = true
            delegate?.didSelectOptionView(self, theme: theme)
        }
    }

    func updateSelectionState() {
        colorViewInsetConstraints?.forEach { $0.isActive = false }
        colorViewInsetConstraints = colorView.autoPinEdgesToSuperviewEdges(
            withInsets: isSelected ? UIEdgeInsets(margin: 4) : .zero
        )

        if isSelected {
            layer.borderColor = Theme.primaryTextColor.cgColor
            layer.borderWidth = 2.5
        } else {
            layer.borderColor = nil
            layer.borderWidth = 0
        }
    }

    func updateTheme() {
        colorView.backgroundColor = theme?.backgroundColor
    }

    private var theme: AvatarTheme? { didSet { updateTheme() }}
    func configure(theme: AvatarTheme, isSelected: Bool) {
        self.theme = theme
        self.isSelected = isSelected
    }
}

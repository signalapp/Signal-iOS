//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class AvatarEditViewController: OWSViewController, OWSNavigationChildController {
    private let originalModel: AvatarModel
    private var model: AvatarModel {
        didSet {
            updateNavigation()
            if isViewLoaded {
                updateHeaderViewState()
            }
        }
    }

    private let completion: (AvatarModel) -> Void

    static let headerAvatarSize: CGFloat = UIDevice.current.isIPhone5OrShorter ? 120 : 160

    init(model: AvatarModel, completion: @escaping (AvatarModel) -> Void) {
        self.originalModel = model
        self.model = model
        self.completion = completion

        super.init()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }

    var navbarBackgroundColorOverride: UIColor? { UIColor.Signal.groupedBackground }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.Signal.groupedBackground

        navigationItem.leftBarButtonItem = .cancelButton(
            dismissingFrom: self,
            hasUnsavedChanges: { [weak self] in
                self?.model != self?.originalModel
            },
        )

        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            self?.didTapDone()
        }

        updateNavigation()
        updateHeaderViewState()
        updateFooterViewState()

        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.frameLayoutGuide.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            scrollView.frameLayoutGuide.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            scrollView.frameLayoutGuide.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor, constant: -8),
        ])

        scrollView.addSubview(topHeader)
        topHeader.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topHeader.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            topHeader.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            topHeader.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            topHeader.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
        ])

        scrollView.addSubview(bottomFooterStack)
        bottomFooterStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bottomFooterStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            bottomFooterStack.topAnchor.constraint(equalTo: topHeader.bottomAnchor),
            bottomFooterStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            bottomFooterStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            bottomFooterStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        ])
    }

    override func themeDidChange() {
        super.themeDidChange()

        optionViews.removeAll()
        updateFooterViewLayout(forceUpdate: true)
    }

    private func didTapDone() {
        defer { dismiss(animated: true) }

        guard model != originalModel else {
            return owsFailDebug("Tried to tap done in unexpected state")
        }

        completion(model)
    }

    private func updateNavigation() {
        let hasUnsavedChanges: Bool

        if case .text(let text) = model.type, text.nilIfEmpty == nil {
            hasUnsavedChanges = false
        } else if model != originalModel {
            hasUnsavedChanges = true
        } else {
            hasUnsavedChanges = false
        }

        navigationItem.rightBarButtonItem?.isEnabled = hasUnsavedChanges
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate { [weak self] _ in
            self?.updateFooterViewLayout()
        } completion: { [weak self] _ in
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
        case text
        case color
    }

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl()

        control.insertSegment(
            withTitle: OWSLocalizedString(
                "AVATAR_EDIT_VIEW_TEXT_SEGMENT",
                comment: "Segment indicating the user can edit the text of the avatar",
            ),
            at: Segments.text.rawValue,
            animated: false,
        )
        control.insertSegment(
            withTitle: OWSLocalizedString(
                "AVATAR_EDIT_VIEW_COLOR_SEGMENT",
                comment: "Segment indicating the user can edit the color of the avatar",
            ),
            at: Segments.color.rawValue,
            animated: false,
        )

        control.selectedSegmentIndex = Segments.color.rawValue

        control.addTarget(
            self,
            action: #selector(segmentedControlDidChange),
            for: .valueChanged,
        )

        return control
    }()

    @objc
    private func segmentedControlDidChange() {
        guard let selectedSegment = Segments(rawValue: segmentedControl.selectedSegmentIndex) else { return }
        switch selectedSegment {
        case .color:
            headerTextField.resignFirstResponder()
            updateFooterViewState()
        case .text:
            headerTextField.becomeFirstResponder()
            updateFooterViewState()
        }
    }

    // MARK: - Header

    private lazy var headerImageView: AvatarImageView = {
        let imageView = AvatarImageView()
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var headerTextField: UITextField = {
        let textField = UITextField()
        textField.adjustsFontSizeToFitWidth = true
        textField.textAlignment = .center
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        textField.returnKeyType = .done
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.isHidden = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    private lazy var topHeader: UIView = {
        headerImageView.addSubview(headerTextField)
        let insets = AvatarBuilder.avatarTextMargins(diameter: Self.headerAvatarSize)
        NSLayoutConstraint.activate([
            headerImageView.widthAnchor.constraint(equalToConstant: Self.headerAvatarSize),
            headerImageView.heightAnchor.constraint(equalToConstant: Self.headerAvatarSize),
            headerTextField.leadingAnchor.constraint(equalTo: headerImageView.leadingAnchor, constant: insets.left),
            headerTextField.trailingAnchor.constraint(equalTo: headerImageView.trailingAnchor, constant: -insets.right),
            headerTextField.topAnchor.constraint(equalTo: headerImageView.topAnchor, constant: insets.top),
            headerTextField.bottomAnchor.constraint(equalTo: headerImageView.bottomAnchor, constant: -insets.bottom),
        ])

        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerImageView)
        NSLayoutConstraint.activate([
            headerImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            headerImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            headerImageView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            headerImageView.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
        ])

        return view
    }()

    private func updateHeaderViewState() {
        switch model.type {
        case .icon:
            headerTextField.isHidden = true
            headerImageView.image = SSKEnvironment.shared.avatarBuilderRef.avatarImage(
                model: model,
                diameterPoints: UInt(Self.headerAvatarSize),
            )
        case .text(let text):
            headerTextField.isHidden = false
            headerTextField.textColor = model.theme.foregroundColor
            headerTextField.font = AvatarBuilder.avatarMaxFont(
                diameter: Self.headerAvatarSize,
                isEmojiOnly: text.containsOnlyEmoji,
            )
            if !headerTextField.isFirstResponder { headerTextField.text = text }
            headerImageView.image = .image(color: model.theme.backgroundColor)
        case .image:
            owsFailDebug("Unexpectedly encountered image model")
        }
    }

    // MARK: - Footer View

    private lazy var bottomFooterStack: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [
            segmentedControlContainer,
            themeHeaderContainer,
            themePickerContainer,
        ])
        stackView.axis = .vertical
        stackView.setCustomSpacing(16, after: segmentedControlContainer)
        return stackView
    }()

    private lazy var segmentedControlContainer: UIView = {
        let container = UIView()
        container.addSubview(segmentedControl)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            segmentedControl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            segmentedControl.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            segmentedControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            segmentedControl.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        return container
    }()

    private lazy var themePickerContainer = UIView()
    private lazy var themeHeaderContainer: UIView = {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "AVATAR_EDIT_VIEW_CHOOSE_A_COLOR",
            comment: "Text prompting the user to choose a color when editing their avatar",
        )
        label.textColor = .Signal.label
        label.font = UIFont.dynamicTypeHeadlineClamped

        let view = UIView()
        view.layoutMargins = UIEdgeInsets(
            hMargin: OWSTableViewController2.cellHInnerMargin * 0.5,
            vMargin: 8,
        )
        view.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
        ])
        return view
    }()

    private func updateFooterViewState() {
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

    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()
        updateFooterViewLayout()
    }

    private var previousSizeReference: CGFloat?
    private func updateFooterViewLayout(forceUpdate: Bool = false) {
        // Update theme options layout only when the view size changes.
        guard view.readableContentGuide.layoutFrame.width != previousSizeReference || forceUpdate else { return }
        previousSizeReference = view.readableContentGuide.layoutFrame.width

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

    private func updateThemePickerContainer() {
        themePickerContainer.removeAllSubviews()
        themePickerContainer.layoutMargins = UIEdgeInsets(
            hMargin: OWSTableViewController2.cellHInnerMargin,
            vMargin: OWSTableViewController2.cellVInnerMargin,
        )
        themePickerContainer.backgroundColor = Theme.tableCell2PresentedBackgroundColor
        themePickerContainer.layer.cornerRadius = OWSTableViewController2.cellRounding

        let rowWidth = max(0, view.readableContentGuide.layoutFrame.width - OWSTableViewController2.cellHInnerMargin * 2)
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
            maxGlyphCount: 3,
        )
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        updateFooterViewState()
        return false
    }

    @objc
    func textFieldDidChange() {
        guard case .text = model.type else { return }
        model.type = .text(headerTextField.text ?? "")
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        segmentedControl.selectedSegmentIndex = Segments.text.rawValue
        updateFooterViewState()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        segmentedControl.selectedSegmentIndex = Segments.color.rawValue
        updateFooterViewState()
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

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            updateSelectionState()
        }
    }

    init(delegate: OptionViewDelegate) {
        self.delegate = delegate

        super.init(frame: .zero)

        layoutMargins = .zero

        addSubview(colorView)
        colorView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            colorView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            colorView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            colorView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            colorView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
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
    private func handleTap() {
        guard let theme else {
            return owsFailDebug("Unexpectedly missing theme in OptionView")
        }

        guard !isSelected else { return }

        isSelected = true
        delegate?.didSelectOptionView(self, theme: theme)
    }

    private func updateSelectionState() {
        layoutMargins = isSelected ? UIEdgeInsets(margin: 4) : .zero

        if isSelected {
            layer.borderColor = UIColor.Signal.label.cgColor
            layer.borderWidth = 2.5
        } else {
            layer.borderColor = nil
            layer.borderWidth = 0
        }
    }

    private func updateTheme() {
        colorView.backgroundColor = theme?.backgroundColor
    }

    private var theme: AvatarTheme? {
        didSet {
            updateTheme()
        }
    }

    func configure(theme: AvatarTheme, isSelected: Bool) {
        self.theme = theme
        self.isSelected = isSelected
    }
}

//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
        shouldAvoidKeyboard = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        updateTableContents()
        updateNavigation()
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

    private let headerImageView = AvatarImageView()
    private let headerTextField = UITextField()
    private let topHeaderStack = UIStackView()
    private func createTopHeader() {
        topHeaderStack.isLayoutMarginsRelativeArrangement = true
        topHeaderStack.axis = .vertical
        topHeaderStack.alignment = .center

        headerTextField.font = AvatarBuilder.avatarMaxFont(diameter: Self.headerAvatarSize)
        headerTextField.adjustsFontSizeToFitWidth = true
        headerTextField.textAlignment = .center
        headerTextField.delegate = self
        headerTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        headerTextField.returnKeyType = .done
        headerTextField.autocorrectionType = .no
        headerTextField.spellCheckingType = .no
        headerImageView.addSubview(headerTextField)
        headerTextField.autoPinEdgesToSuperviewEdges(with: AvatarBuilder.avatarMargins(diameter: Self.headerAvatarSize))
        headerTextField.isHidden = true

        headerImageView.autoSetDimensions(to: CGSize(square: Self.headerAvatarSize))
        headerImageView.isUserInteractionEnabled = true
        topHeaderStack.addArrangedSubview(headerImageView)

        topHeader = topHeaderStack

        updateHeaderView()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let section = OWSTableSection()
        if case .icon = model.type {
            section.headerTitle = NSLocalizedString(
                "AVATAR_EDIT_VIEW_CHOOSE_A_COLOR",
                comment: "Text prompting the user to choose a color when editing their avatar"
            )
        } else {
            let segmentedControlContainer = UIView()
            segmentedControlContainer.addSubview(segmentedControl)
            segmentedControl.autoPinEdgesToSuperviewEdges(with: cellOuterInsetsWithMargin(top: 12, bottom: 10))
            section.customHeaderView = segmentedControlContainer
        }

        let isColorSelected = segmentedControl.selectedSegmentIndex == Segments.color.rawValue
        section.hasBackground = isColorSelected

        section.add(.init { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self = self else { return cell }
            cell.selectionStyle = .none
            if isColorSelected {
                self.configureThemeCell(cell)
            }
            return cell
        } actionBlock: {})
        contents.addSection(section)
    }

    private func updateNavigation() {
        navigationItem.leftBarButtonItem = .init(barButtonSystemItem: .cancel, target: self, action: #selector(didTapCancel))

        if model != originalModel {
            navigationItem.rightBarButtonItem = .init(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate { [weak self] _ in
            self?.updateHeaderView()
        } completion: { [weak self] _ in
            self?.updateHeaderView()
        }
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
            updateTableContents()
        case .text:
            headerTextField.becomeFirstResponder()
            updateTableContents()
        }
    }

    // MARK: - Theme Options

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

    private func configureThemeCell(_ cell: UITableViewCell) {
        let rowWidth = max(0, view.width - (view.safeAreaInsets.totalWidth + cellOuterInsets.totalWidth + Self.cellHInnerMargin * 2))
        let minThemeSize: CGFloat = 66
        let themeSpacing: CGFloat = 16
        let themesPerRow = max(1, Int(floor(rowWidth + themeSpacing) / (minThemeSize + themeSpacing)))
        let themeSize = max(minThemeSize, (rowWidth - (themeSpacing * CGFloat(themesPerRow - 1))) / CGFloat(themesPerRow))

        let vStackView = UIStackView()
        vStackView.axis = .vertical
        vStackView.spacing = themeSpacing
        vStackView.alignment = .leading
        cell.contentView.addSubview(vStackView)
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

    // MARK: - Header

    private var previousSize: CGSize?
    func updateHeaderView() {
        switch model.type {
        case .icon:
            headerTextField.isHidden = true
            headerImageView.image = avatarBuilder.avatarImage(model: model, diameterPoints: UInt(Self.headerAvatarSize))
        case .text(let text):
            headerTextField.isHidden = false
            headerTextField.textColor = model.theme.foregroundColor
            if !headerTextField.isFirstResponder { headerTextField.text = text }
            headerImageView.image = .init(color: model.theme.backgroundColor)
        case .image:
            owsFailDebug("Unexpectedly encountered image model")
        }

        // Update button layout only when the view size changes.
        guard view.frame.size != previousSize else { return }
        previousSize = view.frame.size

        topHeaderStack.layoutMargins = cellOuterInsetsWithMargin(top: 58, bottom: 58)
    }
}

extension AvatarEditViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string,
            maxGlyphCount: 4
        )
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        updateTableContents()
        return false
    }

    @objc
    func textFieldDidChange() {
        guard case .text = model.type else { return }
        model.type = .text(headerTextField.text ?? "")
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        updateTableContents()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        updateTableContents()
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
            layer.borderColor = (theme?.backgroundColor ?? Theme.primaryTextColor).cgColor
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

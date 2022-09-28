// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Combine
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

class SessionAvatarCell: UITableViewCell {
    var disposables: Set<AnyCancellable> = Set()
    private var originalInputValue: String?
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setupViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        setupViewHierarchy()
    }
    
    // MARK: - UI
    
    private let stackView: UIStackView = {
        let stackView: UIStackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = Values.mediumSpacing
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        
        let horizontalSpacing: CGFloat = (UIScreen.main.bounds.size.height < 568 ?
            Values.largeSpacing :
            Values.veryLargeSpacing
        )
        stackView.layoutMargins = UIEdgeInsets(
            top: Values.mediumSpacing,
            leading: horizontalSpacing,
            bottom: Values.mediumSpacing,
            trailing: horizontalSpacing
        )
        stackView.isLayoutMarginsRelativeArrangement = true
        
        return stackView
    }()
    
    fileprivate let profilePictureView: ProfilePictureView = {
        let view: ProfilePictureView = ProfilePictureView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.size = Values.largeProfilePictureSize
        
        return view
    }()
    
    fileprivate let displayNameContainer: UIView = {
        let view: UIView = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityLabel = "Edit name text field"
        view.isAccessibilityElement = true
        
        return view
    }()
    
    private lazy var displayNameLabel: UILabel = {
        let label: UILabel = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .ows_mediumFont(withSize: Values.veryLargeFontSize)
        label.themeTextColor = .textPrimary
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 0
        
        return label
    }()
    
    fileprivate let displayNameTextField: UITextField = {
        let textField: TextField = TextField(placeholder: "Enter a name", usesDefaultHeight: false)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.textAlignment = .center
        textField.accessibilityLabel = "Edit name text field"
        textField.alpha = 0
        
        return textField
    }()
    
    private let descriptionSeparator: Separator = {
        let result: Separator = Separator()
        result.isHidden = true
        
        return result
    }()
    
    private let descriptionLabel: SRCopyableLabel = {
        let label: SRCopyableLabel = SRCopyableLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.themeTextColor = .textPrimary
        label.textAlignment = .center
        label.lineBreakMode = .byCharWrapping
        label.numberOfLines = 0
        
        return label
    }()
    
    private let descriptionActionStackView: UIStackView = {
        let stackView: UIStackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fillEqually
        stackView.spacing = (UIDevice.current.isIPad ? Values.iPadButtonSpacing : Values.mediumSpacing)
        
        if (UIDevice.current.isIPad) {
            stackView.layoutMargins = UIEdgeInsets(
                top: 0,
                left: Values.iPadButtonContainerMargin,
                bottom: 0,
                right: Values.iPadButtonContainerMargin
            )
            stackView.isLayoutMarginsRelativeArrangement = true
        }
        
        return stackView
    }()
    
    private func setupViewHierarchy() {
        self.themeBackgroundColor = nil
        self.selectedBackgroundView = UIView()
        
        contentView.addSubview(stackView)
        
        stackView.addArrangedSubview(profilePictureView)
        stackView.addArrangedSubview(displayNameContainer)
        stackView.addArrangedSubview(descriptionSeparator)
        stackView.addArrangedSubview(descriptionLabel)
        stackView.addArrangedSubview(descriptionActionStackView)
        
        displayNameContainer.addSubview(displayNameLabel)
        displayNameContainer.addSubview(displayNameTextField)
        
        setupLayout()
    }
    
    // MARK: - Layout
    
    private func setupLayout() {
        stackView.pin(to: contentView)
        
        profilePictureView.set(.width, to: profilePictureView.size)
        profilePictureView.set(.height, to: profilePictureView.size)
        
        displayNameLabel.pin(to: displayNameContainer)
        displayNameTextField.center(in: displayNameContainer)
        displayNameTextField.widthAnchor
            .constraint(
                lessThanOrEqualTo: stackView.widthAnchor,
                constant: -(stackView.layoutMargins.left + stackView.layoutMargins.right)
            )
            .isActive = true
        
        descriptionSeparator.set(
            .width,
            to: .width,
            of: stackView,
            withOffset: -(stackView.layoutMargins.left + stackView.layoutMargins.right)
        )
        descriptionActionStackView.set(
            .width,
            to: .width,
            of: stackView,
            withOffset: -(stackView.layoutMargins.left + stackView.layoutMargins.right)
        )
    }
    
    // MARK: - Content
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        self.disposables = Set()
        self.originalInputValue = nil
        self.displayNameLabel.text = nil
        self.displayNameTextField.text = nil
        self.descriptionLabel.font = .ows_lightFont(withSize: Values.smallFontSize)
        self.descriptionLabel.text = nil
        
        self.descriptionSeparator.isHidden = true
        self.descriptionActionStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }
    
    func update(
        threadViewModel: SessionThreadViewModel,
        style: SessionCell.Accessory.ThreadInfoStyle,
        viewController: UIViewController
    ) {
        profilePictureView.update(
            publicKey: threadViewModel.threadId,
            profile: threadViewModel.profile,
            additionalProfile: threadViewModel.additionalProfile,
            threadVariant: threadViewModel.threadVariant,
            openGroupProfilePictureData: threadViewModel.openGroupProfilePictureData,
            useFallbackPicture: (
                threadViewModel.threadVariant == .openGroup &&
                threadViewModel.openGroupProfilePictureData == nil
            ),
            showMultiAvatarForClosedGroup: true
        )
        
        originalInputValue = threadViewModel.profile?.nickname
        displayNameLabel.text = {
            guard !threadViewModel.threadIsNoteToSelf else {
                guard let profile: Profile = threadViewModel.profile else {
                    return Profile.truncated(id: threadViewModel.threadId, truncating: .middle)
                }

                return profile.displayName()
            }
            
            return threadViewModel.displayName
        }()
        descriptionLabel.font = {
            switch style.descriptionStyle {
                case .small: return .ows_lightFont(withSize: Values.smallFontSize)
                case .monoSmall: return Fonts.spaceMono(ofSize: Values.smallFontSize)
                case .monoLarge: return Fonts.spaceMono(
                    ofSize: (isIPhone5OrSmaller ? Values.mediumFontSize : Values.largeFontSize)
                )
            }
        }()
        descriptionLabel.text = threadViewModel.threadId
        descriptionLabel.isHidden = (threadViewModel.threadVariant != .contact)
        descriptionLabel.isUserInteractionEnabled = (
            threadViewModel.threadVariant == .contact ||
            threadViewModel.threadVariant == .openGroup
        )
        displayNameTextField.text = threadViewModel.profile?.nickname
        descriptionSeparator.update(title: style.separatorTitle)
        descriptionSeparator.isHidden = (style.separatorTitle == nil)
        
        style.descriptionActions.forEach { action in
            let result: SessionButton = SessionButton(style: .bordered, size: .medium)
            result.setTitle(action.title, for: UIControl.State.normal)
            result.tapPublisher
                .receive(on: DispatchQueue.main)
                .sink(receiveValue: { [weak result] _ in action.run(result) })
                .store(in: &self.disposables)
            
            descriptionActionStackView.addArrangedSubview(result)
        }
        descriptionActionStackView.isHidden = style.descriptionActions.isEmpty
    }
    
    func update(isEditing: Bool, animated: Bool) {
        let changes = { [weak self] in
            self?.displayNameLabel.alpha = (isEditing ? 0 : 1)
            self?.displayNameTextField.alpha = (isEditing ? 1 : 0)
        }
        let completion: (Bool) -> Void = { [weak self] complete in
            self?.displayNameTextField.text = self?.originalInputValue
        }
        
        if animated {
            UIView.animate(withDuration: 0.25, animations: changes, completion: completion)
        }
        else {
            changes()
            completion(true)
        }
        
        if isEditing {
            displayNameTextField.becomeFirstResponder()
        }
        else {
            displayNameTextField.resignFirstResponder()
        }
    }
}

// MARK: - Compose

extension CombineCompatible where Self: SessionAvatarCell {
    var textPublisher: AnyPublisher<String, Never> {
        return self.displayNameTextField.publisher(for: .editingChanged)
            .map { textField -> String in (textField.text ?? "") }
            .eraseToAnyPublisher()
    }

    var displayNameTapPublisher: AnyPublisher<Void, Never> {
        return self.displayNameContainer.tapPublisher
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    var profilePictureTapPublisher: AnyPublisher<Void, Never> {
        return self.profilePictureView.tapPublisher
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}

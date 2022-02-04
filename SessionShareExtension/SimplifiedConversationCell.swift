import UIKit
import SessionUIKit

final class SimplifiedConversationCell : UITableViewCell {
    var threadViewModel: ThreadViewModel! { didSet { update() } }
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUpViewHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }
    
    // MARK: - UI
    
    private lazy var stackView: UIStackView = {
        let stackView: UIStackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Values.mediumSpacing
        
        return stackView
    }()
    
    private lazy var accentLineView: UIView = {
        let result = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.backgroundColor = Colors.destructive
        
        return result
    }()
    
    private lazy var profilePictureView: ProfilePictureView = {
        let view: ProfilePictureView = ProfilePictureView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var displayNameLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.textColor = Colors.text
        result.lineBreakMode = .byTruncatingTail
        
        return result
    }()
    
    // MARK: - Initialization
    
    private func setUpViewHierarchy() {
        backgroundColor = Colors.cellBackground
        
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = Colors.cellSelected
        self.selectedBackgroundView = selectedBackgroundView
        
        addSubview(stackView)
        
        stackView.addArrangedSubview(accentLineView)
        stackView.addArrangedSubview(profilePictureView)
        stackView.addArrangedSubview(displayNameLabel)
        stackView.addArrangedSubview(UIView.hSpacer(0))
        
        setupLayout()
    }
    
    // MARK: - Layout
    
    private func setupLayout() {
        accentLineView.set(.width, to: Values.accentLineThickness)
        accentLineView.set(.height, to: 68)
        
        let profilePictureViewSize = Values.mediumProfilePictureSize
        profilePictureView.set(.width, to: profilePictureViewSize)
        profilePictureView.set(.height, to: profilePictureViewSize)
        profilePictureView.size = profilePictureViewSize
        
        stackView.pin(to: self)
    }
    
    // MARK: - Content
    
    private func update() {
        AssertIsOnMainThread()
        
        guard let thread = threadViewModel?.threadRecord else { return }
        
        let isBlocked: Bool
        if let thread = thread as? TSContactThread {
            isBlocked = SSKEnvironment.shared.blockingManager.isRecipientIdBlocked(thread.contactSessionID())
        } else {
            isBlocked = false
        }
        
        accentLineView.alpha = (isBlocked ? 1 : 0)
        profilePictureView.update(for: thread)
        displayNameLabel.text = getDisplayName()
    }
    
    private func getDisplayName() -> String {
        if threadViewModel.isGroupThread {
            if threadViewModel.name.isEmpty {
                // TODO: Localization
                return "Unknown Group"
            }
            
            return threadViewModel.name
        }
        
        if threadViewModel.threadRecord.isNoteToSelf() {
            return "NOTE_TO_SELF".localized()
        }
        
        guard let hexEncodedPublicKey: String = threadViewModel.contactSessionID else {
            // TODO: Localization
            return "Unknown"
        }
        
        return (
            Storage.shared.getContact(with: hexEncodedPublicKey)?.displayName(for: .regular) ??
            hexEncodedPublicKey
        )
    }
}

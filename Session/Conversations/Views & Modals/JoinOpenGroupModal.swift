// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import SessionMessagingKit
import SessionUtilitiesKit

final class JoinOpenGroupModal: Modal {
    private let name: String
    private let url: String
    
    // MARK: - Lifecycle
    
    init(name: String?, url: String) {
        self.name = (name ?? "Open Group")
        self.url = url
        
        super.init()
    }
    
    override init(afterClosed: (() -> ())? = nil) {
        preconditionFailure("Use init(name:url:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(name:url:) instead.")
    }
    
    override func populateContentView() {
        // Title
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = "Join \(name)?"
        titleLabel.textAlignment = .center
        
        // Message
        let messageLabel = UILabel()
        messageLabel.textColor = Colors.text
        messageLabel.font = .systemFont(ofSize: Values.smallFontSize)
        let message = "Are you sure you want to join the \(name) open group?";
        let attributedMessage = NSMutableAttributedString(string: message)
        attributedMessage.addAttributes([ .font : UIFont.boldSystemFont(ofSize: Values.smallFontSize) ], range: (message as NSString).range(of: name))
        messageLabel.attributedText = attributedMessage
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.textAlignment = .center
        
        // Join button
        let joinButton = UIButton()
        joinButton.set(.height, to: Values.mediumButtonHeight)
        joinButton.layer.cornerRadius = Modal.buttonCornerRadius
        joinButton.backgroundColor = Colors.buttonBackground
        joinButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        joinButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        joinButton.setTitle("Join", for: UIControl.State.normal)
        joinButton.addTarget(self, action: #selector(joinOpenGroup), for: UIControl.Event.touchUpInside)
        
        // Button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ cancelButton, joinButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.distribution = .fillEqually
        
        // Content stack view
        let contentStackView = UIStackView(arrangedSubviews: [ titleLabel, messageLabel ])
        contentStackView.axis = .vertical
        contentStackView.spacing = Values.largeSpacing
        
        // Main stack view
        let spacing = Values.largeSpacing - Values.smallFontSize / 2
        let mainStackView = UIStackView(arrangedSubviews: [ contentStackView, buttonStackView ])
        mainStackView.axis = .vertical
        mainStackView.spacing = spacing
        contentView.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: spacing)
    }
    
    // MARK: - Interaction
    
    @objc private func joinOpenGroup() {
        guard let presentingViewController: UIViewController = self.presentingViewController else { return }
        guard let (room, server, publicKey) = OpenGroupManager.parseOpenGroup(from: url) else {
            let alert = UIAlertController(title: "Couldn't Join", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "BUTTON_OK".localized(), style: .default, handler: nil))
            
            return presentingViewController.present(alert, animated: true, completion: nil)
        }
        
        presentingViewController.dismiss(animated: true, completion: nil)
        
        Storage.shared
            .writeAsync { db in
                OpenGroupManager.shared.add(
                    db,
                    roomToken: room,
                    server: server,
                    publicKey: publicKey,
                    isConfigMessage: false
                )
            }
            .done(on: DispatchQueue.main) { _ in
                Storage.shared.writeAsync { db in
                    try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete() // FIXME: It's probably cleaner to do this inside addOpenGroup(...)
                }
            }
            .catch(on: DispatchQueue.main) { error in
                let alert = UIAlertController(title: "Couldn't Join", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "BUTTON_OK".localized(), style: .default, handler: nil))
                presentingViewController.present(alert, animated: true, completion: nil)
            }
            .retainUntilComplete()
    }
}

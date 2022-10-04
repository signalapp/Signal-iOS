// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

final class ExpandingAttachmentsButton: UIView, InputViewButtonDelegate {
    private weak var delegate: ExpandingAttachmentsButtonDelegate?
    private var isExpanded = false { didSet { expandOrCollapse() } }
    
    override var isUserInteractionEnabled: Bool {
        didSet {
            gifButton.isUserInteractionEnabled = isUserInteractionEnabled
            documentButton.isUserInteractionEnabled = isUserInteractionEnabled
            libraryButton.isUserInteractionEnabled = isUserInteractionEnabled
            cameraButton.isUserInteractionEnabled = isUserInteractionEnabled
            mainButton.isUserInteractionEnabled = isUserInteractionEnabled
        }
    }
    
    // MARK: Constraints
    private lazy var gifButtonContainerBottomConstraint = gifButtonContainer.pin(.bottom, to: .bottom, of: self)
    private lazy var documentButtonContainerBottomConstraint = documentButtonContainer.pin(.bottom, to: .bottom, of: self)
    private lazy var libraryButtonContainerBottomConstraint = libraryButtonContainer.pin(.bottom, to: .bottom, of: self)
    private lazy var cameraButtonContainerBottomConstraint = cameraButtonContainer.pin(.bottom, to: .bottom, of: self)
    
    // MARK: UI Components
    lazy var gifButton: InputViewButton = {
        let result = InputViewButton(icon: #imageLiteral(resourceName: "actionsheet_gif_black"), delegate: self, hasOpaqueBackground: true)
        result.accessibilityLabel = "accessibility_gif_button".localized()
        
        return result
    }()
    lazy var gifButtonContainer = container(for: gifButton)
    lazy var documentButton: InputViewButton = {
        let result = InputViewButton(icon: #imageLiteral(resourceName: "actionsheet_document_black"), delegate: self, hasOpaqueBackground: true)
        result.accessibilityLabel = "accessibility_document_button".localized()
        
        return result
    }()
    lazy var documentButtonContainer = container(for: documentButton)
    lazy var libraryButton: InputViewButton = {
        let result = InputViewButton(icon: #imageLiteral(resourceName: "actionsheet_camera_roll_black"), delegate: self, hasOpaqueBackground: true)
        result.accessibilityLabel = "accessibility_library_button".localized()
        
        return result
    }()
    lazy var libraryButtonContainer = container(for: libraryButton)
    lazy var cameraButton: InputViewButton = {
        let result = InputViewButton(icon: #imageLiteral(resourceName: "actionsheet_camera_black"), delegate: self, hasOpaqueBackground: true)
        result.accessibilityLabel = "accessibility_camera_button".localized()
        
        return result
    }()
    lazy var cameraButtonContainer = container(for: cameraButton)
    lazy var mainButton: InputViewButton = {
        let result = InputViewButton(icon: #imageLiteral(resourceName: "ic_plus_24"), delegate: self)
        result.accessibilityLabel = "accessibility_expanding_attachments_button".localized()
        
        return result
    }()
    lazy var mainButtonContainer = container(for: mainButton)
    
    // MARK: Lifecycle
    init(delegate: ExpandingAttachmentsButtonDelegate?) {
        self.delegate = delegate
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(delegate:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(delegate:) instead.")
    }
    
    private func setUpViewHierarchy() {
        backgroundColor = .clear
        // GIF button
        addSubview(gifButtonContainer)
        gifButtonContainer.alpha = 0
        // Document button
        addSubview(documentButtonContainer)
        documentButtonContainer.alpha = 0
        // Library button
        addSubview(libraryButtonContainer)
        libraryButtonContainer.alpha = 0
        // Camera button
        addSubview(cameraButtonContainer)
        cameraButtonContainer.alpha = 0
        // Main button
        addSubview(mainButtonContainer)
        // Constraints
        mainButtonContainer.pin(to: self)
        gifButtonContainer.center(.horizontal, in: self)
        documentButtonContainer.center(.horizontal, in: self)
        libraryButtonContainer.center(.horizontal, in: self)
        cameraButtonContainer.center(.horizontal, in: self)
        [ gifButtonContainerBottomConstraint, documentButtonContainerBottomConstraint, libraryButtonContainerBottomConstraint, cameraButtonContainerBottomConstraint ].forEach {
            $0.isActive = true
        }
    }
    
    // MARK: Animation
    private func expandOrCollapse() {
        if isExpanded {
            mainButton.accessibilityLabel = NSLocalizedString("accessibility_main_button_collapse", comment: "")
            let expandedButtonSize = InputViewButton.expandedSize
            let spacing: CGFloat = 4
            cameraButtonContainerBottomConstraint.constant = -1 * (expandedButtonSize + spacing)
            libraryButtonContainerBottomConstraint.constant = -2 * (expandedButtonSize + spacing)
            documentButtonContainerBottomConstraint.constant = -3 * (expandedButtonSize + spacing)
            gifButtonContainerBottomConstraint.constant = -4 * (expandedButtonSize + spacing)
            UIView.animate(withDuration: 0.25) {
                [ self.gifButtonContainer, self.documentButtonContainer, self.libraryButtonContainer, self.cameraButtonContainer ].forEach {
                    $0.alpha = 1
                }
                self.layoutIfNeeded()
            }
        } else {
            mainButton.accessibilityLabel = NSLocalizedString("accessibility_expanding_attachments_button", comment: "")
            [ gifButtonContainerBottomConstraint, documentButtonContainerBottomConstraint, libraryButtonContainerBottomConstraint, cameraButtonContainerBottomConstraint ].forEach {
                $0.constant = 0
            }
            UIView.animate(withDuration: 0.25) {
                [ self.gifButtonContainer, self.documentButtonContainer, self.libraryButtonContainer, self.cameraButtonContainer ].forEach {
                    $0.alpha = 0
                }
                self.layoutIfNeeded()
            }
        }
    }
    
    // MARK: Interaction
    func handleInputViewButtonTapped(_ inputViewButton: InputViewButton) {
        if inputViewButton == gifButton { delegate?.handleGIFButtonTapped(); isExpanded = false }
        if inputViewButton == documentButton { delegate?.handleDocumentButtonTapped(); isExpanded = false }
        if inputViewButton == libraryButton { delegate?.handleLibraryButtonTapped(); isExpanded = false }
        if inputViewButton == cameraButton { delegate?.handleCameraButtonTapped(); isExpanded = false }
        if inputViewButton == mainButton { isExpanded = !isExpanded }
    }
    
    // MARK: Convenience
    private func container(for button: InputViewButton) -> UIView {
        let result = UIView()
        result.addSubview(button)
        result.set(.width, to: InputViewButton.expandedSize)
        result.set(.height, to: InputViewButton.expandedSize)
        button.center(in: result)
        return result
    }
}

// MARK: - Delegate

protocol ExpandingAttachmentsButtonDelegate: AnyObject {

    func handleGIFButtonTapped()
    func handleDocumentButtonTapped()
    func handleLibraryButtonTapped()
    func handleCameraButtonTapped()
}

// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import NVActivityIndicatorView
import SessionUIKit
import SessionMessagingKit

final class LinkPreviewView: UIView {
    private static let loaderSize: CGFloat = 24
    private static let cancelButtonSize: CGFloat = 45
    
    private let maxWidth: CGFloat
    private let onCancel: (() -> ())?

    // MARK: - UI
    
    private lazy var imageViewContainerWidthConstraint = imageView.set(.width, to: 100)
    private lazy var imageViewContainerHeightConstraint = imageView.set(.height, to: 100)

    // MARK: UI Components

    private lazy var imageView: UIImageView = {
        let result: UIImageView = UIImageView()
        result.contentMode = .scaleAspectFill
        
        return result
    }()

    private lazy var imageViewContainer: UIView = {
        let result: UIView = UIView()
        result.clipsToBounds = true
        
        return result
    }()

    private lazy var loader: NVActivityIndicatorView = {
        // FIXME: This will have issues with theme transitions
        let color: UIColor = (isLightMode ? .black : .white)
        
        return NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: color, padding: nil)
    }()

    private lazy var titleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.numberOfLines = 0
        
        return result
    }()

    private lazy var bodyTappableLabelContainer: UIView = UIView()

    private lazy var hStackViewContainer: UIView = UIView()

    private lazy var hStackView: UIStackView = UIStackView()

    private lazy var cancelButton: UIButton = {
        // FIXME: This will have issues with theme transitions
        let result: UIButton = UIButton(type: .custom)
        result.setImage(UIImage(named: "X")?.withRenderingMode(.alwaysTemplate), for: UIControl.State.normal)
        result.tintColor = (isLightMode ? .black : .white)
        
        let cancelButtonSize = LinkPreviewView.cancelButtonSize
        result.set(.width, to: cancelButtonSize)
        result.set(.height, to: cancelButtonSize)
        result.addTarget(self, action: #selector(cancel), for: UIControl.Event.touchUpInside)
        
        return result
    }()
    
    var bodyTappableLabel: TappableLabel?

    // MARK: - Initialization
    
    init(maxWidth: CGFloat, onCancel: (() -> ())? = nil) {
        self.maxWidth = maxWidth
        self.onCancel = onCancel
        
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy()
    }

    override init(frame: CGRect) {
        preconditionFailure("Use init(for:maxWidth:delegate:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(for:maxWidth:delegate:) instead.")
    }

    private func setUpViewHierarchy() {
        // Image view
        imageViewContainerWidthConstraint.isActive = true
        imageViewContainerHeightConstraint.isActive = true
        imageViewContainer.addSubview(imageView)
        imageView.pin(to: imageViewContainer)
        
        // Title label
        let titleLabelContainer = UIView()
        titleLabelContainer.addSubview(titleLabel)
        titleLabel.pin(to: titleLabelContainer, withInset: Values.smallSpacing)
        
        // Horizontal stack view
        hStackView.addArrangedSubview(imageViewContainer)
        hStackView.addArrangedSubview(titleLabelContainer)
        hStackView.axis = .horizontal
        hStackView.alignment = .center
        hStackViewContainer.addSubview(hStackView)
        hStackView.pin(to: hStackViewContainer)
        
        // Vertical stack view
        let vStackView = UIStackView(arrangedSubviews: [ hStackViewContainer, bodyTappableLabelContainer ])
        vStackView.axis = .vertical
        addSubview(vStackView)
        vStackView.pin(to: self)
        
        // Loader
        addSubview(loader)
        
        let loaderSize = LinkPreviewView.loaderSize
        loader.set(.width, to: loaderSize)
        loader.set(.height, to: loaderSize)
        loader.center(in: self)
    }

    // MARK: - Updating
    
    public func update(
        with state: LinkPreviewState,
        isOutgoing: Bool,
        delegate: TappableLabelDelegate? = nil,
        cellViewModel: MessageViewModel? = nil,
        bodyLabelTextColor: UIColor? = nil,
        lastSearchText: String? = nil
    ) {
        cancelButton.removeFromSuperview()
        
        var image: UIImage? = state.image
        let stateHasImage: Bool = (image != nil)
        if image == nil && (state is LinkPreview.DraftState || state is LinkPreview.SentState) {
            image = UIImage(named: "Link")?.withTint(isLightMode ? .black : .white)
        }
        
        // Image view
        let imageViewContainerSize: CGFloat = (state is LinkPreview.SentState ? 100 : 80)
        imageViewContainerWidthConstraint.constant = imageViewContainerSize
        imageViewContainerHeightConstraint.constant = imageViewContainerSize
        imageViewContainer.layer.cornerRadius = (state is LinkPreview.SentState ? 0 : 8)
        
        if state is LinkPreview.LoadingState {
            imageViewContainer.backgroundColor = .clear
        }
        else {
            imageViewContainer.backgroundColor = isDarkMode ? .black : UIColor.black.withAlphaComponent(0.06)
        }
        
        imageView.image = image
        imageView.contentMode = (stateHasImage ? .scaleAspectFill : .center)
        
        // Loader
        loader.alpha = (image != nil ? 0 : 1)
        if image != nil { loader.stopAnimating() } else { loader.startAnimating() }
        
        // Title
        let sentLinkPreviewTextColor: UIColor = {
            switch (isOutgoing, AppModeManager.shared.currentAppMode) {
                case (false, .light): return .black
                case (true, .light): return Colors.grey
                default: return .white
            }
        }()
        titleLabel.textColor = sentLinkPreviewTextColor
        titleLabel.text = state.title
        
        // Horizontal stack view
        switch state {
            case is LinkPreview.SentState:
                // FIXME: This will have issues with theme transitions
                hStackViewContainer.backgroundColor = (isDarkMode ? .black : UIColor.black.withAlphaComponent(0.06))
                
            default:
                hStackViewContainer.backgroundColor = nil
        }
        
        // Body text view
        bodyTappableLabelContainer.subviews.forEach { $0.removeFromSuperview() }
        
        if let cellViewModel: MessageViewModel = cellViewModel {
            let bodyTappableLabel = VisibleMessageCell.getBodyTappableLabel(
                for: cellViewModel,
                with: maxWidth,
                textColor: (bodyLabelTextColor ?? sentLinkPreviewTextColor),
                searchText: lastSearchText,
                delegate: delegate
            )
            
            self.bodyTappableLabel = bodyTappableLabel
            bodyTappableLabelContainer.addSubview(bodyTappableLabel)
            bodyTappableLabel.pin(to: bodyTappableLabelContainer, withInset: 12)
        }
        
        if state is LinkPreview.DraftState {
            hStackView.addArrangedSubview(cancelButton)
        }
    }

    // MARK: - Interaction
    
    @objc private func cancel() {
        onCancel?()
    }
}

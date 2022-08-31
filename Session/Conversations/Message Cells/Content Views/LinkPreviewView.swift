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

    private let loader: NVActivityIndicatorView = {
        let result: NVActivityIndicatorView = NVActivityIndicatorView(
            frame: CGRect.zero,
            type: .circleStrokeSpin,
            color: .black,
            padding: nil
        )
        
        ThemeManager.onThemeChange(observer: result) { [weak result] theme, _ in
            guard let textPrimary: UIColor = theme.colors[.textPrimary] else { return }
            
            result?.color = textPrimary
        }
        
        return result
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
        bodyLabelTextColor: ThemeValue? = nil,
        lastSearchText: String? = nil
    ) {
        cancelButton.removeFromSuperview()
        
        var image: UIImage? = state.image
        let stateHasImage: Bool = (image != nil)
        if image == nil && (state is LinkPreview.DraftState || state is LinkPreview.SentState) {
            image = UIImage(named: "Link")?.withRenderingMode(.alwaysTemplate)
        }
        
        // Image view
        let imageViewContainerSize: CGFloat = (state is LinkPreview.SentState ? 100 : 80)
        imageViewContainerWidthConstraint.constant = imageViewContainerSize
        imageViewContainerHeightConstraint.constant = imageViewContainerSize
        imageViewContainer.layer.cornerRadius = (state is LinkPreview.SentState ? 0 : 8)
        
        imageView.image = image
        imageView.themeTintColor = (isOutgoing ?
            .messageBubble_outgoingText :
            .messageBubble_incomingText
        )
        imageView.contentMode = (stateHasImage ? .scaleAspectFill : .center)
        
        // Loader
        loader.alpha = (image != nil ? 0 : 1)
        if image != nil { loader.stopAnimating() } else { loader.startAnimating() }
        
        // Title
        titleLabel.text = state.title
        titleLabel.themeTextColor = (isOutgoing ?
            .messageBubble_outgoingText :
            .messageBubble_incomingText
        )
        
        // Horizontal stack view
        switch state {
            case is LinkPreview.LoadingState:
                imageViewContainer.themeBackgroundColor = .clear
                hStackViewContainer.themeBackgroundColor = nil
                
            case is LinkPreview.SentState:
                imageViewContainer.themeBackgroundColor = .messageBubble_overlay
                hStackViewContainer.themeBackgroundColor = .messageBubble_overlay
                
            default:
                imageViewContainer.themeBackgroundColor = .messageBubble_overlay
                hStackViewContainer.themeBackgroundColor = nil
        }
        
        // Body text view
        bodyTappableLabelContainer.subviews.forEach { $0.removeFromSuperview() }
        
        if let cellViewModel: MessageViewModel = cellViewModel {
            let bodyTappableLabel = VisibleMessageCell.getBodyTappableLabel(
                for: cellViewModel,
                with: maxWidth,
                textColor: (bodyLabelTextColor ?? .textPrimary),
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

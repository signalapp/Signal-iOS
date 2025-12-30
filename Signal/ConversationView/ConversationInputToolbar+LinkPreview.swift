//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class OutgoingLinkPreviewView: UIView {

    init(state: LinkPreviewFetchState.State) {
        super.init(frame: .zero)

        directionalLayoutMargins = .init(top: 0, leading: 12, bottom: 0, trailing: 0)

        if #available(iOS 26, *) {
            clipsToBounds = true
            cornerConfiguration = .uniformCorners(radius: .containerConcentric(minimum: 12))
        }

        let backgroundView = UIView()
        backgroundView.backgroundColor = .Signal.secondaryFill
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])

        configure(withState: state)
    }

    // We need rounded corners on the whole view (and not background) because image view
    // is constrained to view's top, bottom and trailing edges.
    override var bounds: CGRect {
        didSet {
            // Use `cornerConfiguration`.
            if #available(iOS 26, *) { return }

            // Mask to round corners.
            let maskLayer = CAShapeLayer()
            maskLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: 12).cgPath
            layer.mask = maskLayer
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private let contentView = UIView()

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingVerticalHigh()
        // Lower than vertical hugging of text labels so image view's height is constrained by text.
        imageView.setCompressionResistanceVerticalLow()
        return imageView
    }()

    private static let imageSize = CGSize(width: 77, height: 77)

    // (X) button.
    let cancelButton: UIButton = {
        let cancelButton = UIButton(configuration: .bordered())
        cancelButton.configuration?.image = UIImage(imageLiteralResourceName: "x-compact-bold")
        cancelButton.configuration?.baseBackgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(rgbHex: 0x787880, alpha: 0.4)
                : UIColor(rgbHex: 0xF5F5F5, alpha: 0.9)
        }
        cancelButton.configuration?.background.visualEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        cancelButton.tintColor = ConversationInputToolbar.Style.primaryTextColor
        cancelButton.configuration?.cornerStyle = .capsule
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cancelButton.widthAnchor.constraint(equalToConstant: 24),
            cancelButton.heightAnchor.constraint(equalToConstant: 24),
        ])
        return cancelButton
    }()

    func resetContent() {
        contentView.removeAllSubviews()
        imageView.image = nil
    }

    func configure(withState state: LinkPreviewFetchState.State) {
        resetContent()

        switch state {
        case .loading:
            configureAsLoading()
        case .loaded(let linkPreviewDraft):
            let draft = LinkPreviewDraft(linkPreviewDraft: linkPreviewDraft)
            if CallLink(url: linkPreviewDraft.url) != nil {
                configureAsCallLinkPreviewDraft(draft: draft)
            } else {
                configureAsLinkPreviewDraft(draft: draft)
            }
        default:
            owsFailBeta("Invalid link preview state: [\(state)]")
        }
    }

    private func configureAsLoading() {
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.tintColor = ConversationInputToolbar.Style.secondaryTextColor
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentView.topAnchor, constant: 0.5 * Self.imageSize.height),
        ])

        activityIndicator.startAnimating()
    }

    private func configureAsLinkPreviewDraft(draft: LinkPreviewDraft) {
        // Text
        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.directionalLayoutMargins = .zero
        textStack.isLayoutMarginsRelativeArrangement = true

        if let text = draft.title?.nilIfEmpty {
            let label = UILabel()
            label.text = text
            label.textColor = ConversationInputToolbar.Style.primaryTextColor
            label.numberOfLines = 2
            label.adjustsFontForContentSizeCategory = true
            label.font = .dynamicTypeFootnote.semibold()
            label.lineBreakMode = .byTruncatingTail
            label.setContentHuggingVerticalHigh()
            textStack.addArrangedSubview(label)
            textStack.setCustomSpacing(2, after: label)
        }

        if let text = draft.previewDescription?.nilIfEmpty {
            let label = UILabel()
            label.text = text
            label.textColor = ConversationInputToolbar.Style.primaryTextColor
            label.numberOfLines = 2
            label.adjustsFontForContentSizeCategory = true
            label.font = .dynamicTypeFootnote
            label.lineBreakMode = .byTruncatingTail
            label.setContentHuggingVerticalHigh()
            textStack.addArrangedSubview(label)
        }

        if let displayDomain = draft.displayDomain?.nilIfEmpty {
            var text = displayDomain.lowercased()
            if let date = draft.date {
                text.append(" ⋅ \(Self.dateFormatter.string(from: date))")
            }
            let label = UILabel()
            label.text = text
            label.textColor = ConversationInputToolbar.Style.secondaryTextColor
            label.numberOfLines = 1
            label.adjustsFontForContentSizeCategory = true
            label.font = .dynamicTypeCaption1
            label.lineBreakMode = .byTruncatingTail
            label.setContentHuggingVerticalHigh()
            textStack.addArrangedSubview(label)
        }

        let textStackContainer = UIView.container()
        textStackContainer.addSubview(textStack)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(greaterThanOrEqualTo: textStackContainer.topAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: textStackContainer.centerYAnchor),
            textStack.leadingAnchor.constraint(equalTo: textStackContainer.leadingAnchor),
            textStack.trailingAnchor.constraint(equalTo: textStackContainer.trailingAnchor),
            {
                let c = textStack.topAnchor.constraint(equalTo: textStackContainer.topAnchor)
                c.priority = .defaultHigh
                return c
            }(),
        ])

        let horizontalStack = UIStackView(arrangedSubviews: [textStackContainer])
        horizontalStack.axis = .horizontal
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(horizontalStack)
        NSLayoutConstraint.activate([
            horizontalStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            horizontalStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            horizontalStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            horizontalStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // Image
        let cancelButtonPadding: CGFloat = 8 // around all edges
        if draft.imageState == .loaded {
            textStack.directionalLayoutMargins.trailing = 12 // spacing between text and image

            imageView.contentMode = .scaleAspectFill
            draft.imageAsync(thumbnailQuality: .small) { [weak self] image in
                DispatchMainThreadSafe {
                    guard let self else { return }
                    self.imageView.image = image
                }
            }
            horizontalStack.addArrangedSubview(imageView)
            horizontalStack.addSubview(cancelButton)
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: Self.imageSize.width),
                // Allow image view to grow with text.
                imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.imageSize.height),

                cancelButton.topAnchor.constraint(equalTo: imageView.topAnchor, constant: cancelButtonPadding),
                cancelButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -cancelButtonPadding),
            ])
        } else {
            textStack.directionalLayoutMargins.trailing = 0 // `cancelButtonContainer` has enough spacing between cancel button and text

            let cancelButtonContainer = UIView.container()
            cancelButtonContainer.addSubview(cancelButton)
            NSLayoutConstraint.activate([
                cancelButton.topAnchor.constraint(equalTo: cancelButtonContainer.topAnchor, constant: cancelButtonPadding),
                cancelButton.leadingAnchor.constraint(equalTo: cancelButtonContainer.leadingAnchor, constant: cancelButtonPadding),
                cancelButton.trailingAnchor.constraint(equalTo: cancelButtonContainer.trailingAnchor, constant: -cancelButtonPadding),
                cancelButton.bottomAnchor.constraint(lessThanOrEqualTo: cancelButtonContainer.bottomAnchor, constant: -cancelButtonPadding),
            ])
            horizontalStack.addArrangedSubview(cancelButtonContainer)
        }
    }

    private func configureAsCallLinkPreviewDraft(draft: LinkPreviewDraft) {
        // Image
        let imageSize: CGFloat = 27
        let cameraIcon = UIImageView(image: UIImage(imageLiteralResourceName: "video"))
        cameraIcon.tintColor = .init(rgbHex: 0x4F4F69)

        let circleSize: CGFloat = 48
        let circleView = CircleView()
        circleView.backgroundColor = .init(rgbHex: 0xD2D2DA)
        circleView.addSubview(cameraIcon)

        let imageContainer = UIView.container()
        imageContainer.addSubview(circleView)

        cameraIcon.translatesAutoresizingMaskIntoConstraints = false
        circleView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cameraIcon.widthAnchor.constraint(equalToConstant: imageSize),
            cameraIcon.heightAnchor.constraint(equalToConstant: imageSize),

            cameraIcon.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            cameraIcon.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),

            circleView.widthAnchor.constraint(equalToConstant: circleSize),
            circleView.heightAnchor.constraint(equalToConstant: circleSize),

            circleView.topAnchor.constraint(equalTo: imageContainer.topAnchor, constant: 4),
            circleView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            circleView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            circleView.bottomAnchor.constraint(lessThanOrEqualTo: imageContainer.bottomAnchor),
        ])

        // Text
        let textStack = UIStackView(arrangedSubviews: [])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.isLayoutMarginsRelativeArrangement = true
        textStack.directionalLayoutMargins = .init(hMargin: 0, vMargin: 4)

        let titleLabel = UILabel()
        titleLabel.text = CallStrings.signalCall
        titleLabel.textColor = ConversationInputToolbar.Style.primaryTextColor
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = .dynamicTypeFootnote.semibold()
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentHuggingVerticalHigh()
        textStack.addArrangedSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.text = CallStrings.callLinkDescription
        subtitleLabel.textColor = ConversationInputToolbar.Style.primaryTextColor
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.font = .dynamicTypeFootnote
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentHuggingVerticalHigh()
        textStack.addArrangedSubview(subtitleLabel)

        if let displayDomain = draft.displayDomain?.nilIfEmpty {
            var text = displayDomain.lowercased()
            if let date = draft.date {
                text.append(" ⋅ \(Self.dateFormatter.string(from: date))")
            }
            let label = UILabel()
            label.text = text
            label.textColor = ConversationInputToolbar.Style.secondaryTextColor
            label.numberOfLines = 1
            label.adjustsFontForContentSizeCategory = true
            label.font = .dynamicTypeCaption1
            label.lineBreakMode = .byTruncatingTail
            label.setContentHuggingVerticalHigh()
            textStack.addArrangedSubview(label)
        }

        // Cancel button
        let cancelButtonContainer = UIView.container()
        cancelButtonContainer.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: cancelButtonContainer.topAnchor),
            cancelButton.leadingAnchor.constraint(equalTo: cancelButtonContainer.leadingAnchor, constant: 6),
            cancelButton.trailingAnchor.constraint(equalTo: cancelButtonContainer.trailingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(lessThanOrEqualTo: cancelButtonContainer.bottomAnchor),
        ])

        let horizontalStack = UIStackView(arrangedSubviews: [imageContainer, textStack, cancelButtonContainer])
        horizontalStack.axis = .horizontal
        horizontalStack.setCustomSpacing(12, after: imageContainer)
        horizontalStack.isLayoutMarginsRelativeArrangement = true
        horizontalStack.directionalLayoutMargins = .init(hMargin: 0, vMargin: 8)
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(horizontalStack)
        NSLayoutConstraint.activate([
            horizontalStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            horizontalStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            horizontalStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            horizontalStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
}

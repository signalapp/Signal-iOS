//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Blocks use of the app, explaining to the user why and what they can do
/// about it.
///
/// Subclass to describe a specific blocking scenario. Presentation, and any
/// navigation affordances such as a cancel button, are the caller's
/// responsibility.
open class AppBlockingViewController: OWSViewController {

    private enum Constants {
        static let headerImageSize: CGFloat = 64
        static let spacing: CGFloat = 16
        static let spacingAfterHeaderImage: CGFloat = 24
        static let margin: CGFloat = 40
    }

    private let headerImage: UIImage
    private let titleText: String

    /// Settable, for subclasses whose subtitle changes while they're displayed.
    public var subtitle: String {
        didSet {
            guard isViewLoaded else { return }
            subtitleLabel.text = subtitle
        }
    }

    public init(headerImage: UIImage, title: String, subtitle: String) {
        self.headerImage = headerImage
        self.titleText = title
        self.subtitle = subtitle

        super.init()
    }

    // MARK: - Views

    private lazy var headerImageView: UIImageView = {
        let imageView = UIImageView(image: headerImage)
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .Signal.label
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: Constants.headerImageSize),
            imageView.heightAnchor.constraint(equalToConstant: Constants.headerImageSize),
        ])
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel.headlineLabel(text: titleText, semibold: true)
        label.textAlignment = .center
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel.subheadlineLabel(text: subtitle)
        label.textColor = .Signal.secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [
            headerImageView,
            titleLabel,
            subtitleLabel,
        ])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Constants.spacing
        stack.setCustomSpacing(Constants.spacingAfterHeaderImage, after: headerImageView)
        return stack
    }()

    // MARK: - Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Constants.margin,
            leading: Constants.margin,
            bottom: Constants.margin,
            trailing: Constants.margin,
        )
        view.addSubview(contentStack)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.topAnchor),
            contentStack.centerYAnchor.constraint(equalTo: view.layoutMarginsGuide.centerYAnchor),

            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            contentStack.centerXAnchor.constraint(equalTo: view.layoutMarginsGuide.centerXAnchor),
        ])
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    AppBlockingViewController(
        headerImage: UIImage(named: "signal-logo-128-launch-screen")!,
        title: "Something Went Wrong",
        subtitle: "Something went wrong and the app can't run. Whoops!",
    )
}

#endif

//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

class ChatListBackupProgressView: UIView {

    static func configure(
        label: UILabel,
        font: UIFont = .dynamicTypeSubheadline,
        color: UIColor,
    ) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.adjustsFontForContentSizeCategory = true
        label.font = .monospacedDigitFont(ofSize: font.pointSize)
        label.textColor = color
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
    }

    // MARK: -

    private lazy var leadingAccessoryImageView = UIImageView()

    private lazy var labelStackView = UIStackView()
    private lazy var titleLabel = UILabel()
    private lazy var progressLabel = UILabel()

    /// A container for the various trailingAccessory views we might display. A
    /// stack view so we can use `isHidden = true` to make subviews take up zero
    /// space.
    private lazy var trailingAccessoryContainerView = UIStackView()

    init() {
        super.init(frame: .zero)

        backgroundColor = .Signal.quaternaryFill
        layer.cornerRadius = 24
        layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 12)

        addSubview(leadingAccessoryImageView)
        leadingAccessoryImageView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(labelStackView)
        labelStackView.translatesAutoresizingMaskIntoConstraints = false
        labelStackView.alignment = .fill
        labelStackView.axis = .vertical
        labelStackView.spacing = 4

        labelStackView.addArrangedSubview(titleLabel)
        Self.configure(label: titleLabel, color: .Signal.label)

        labelStackView.addArrangedSubview(progressLabel)
        Self.configure(label: progressLabel, font: .dynamicTypeFootnote, color: .Signal.secondaryLabel)

        addSubview(trailingAccessoryContainerView)
        trailingAccessoryContainerView.alignment = .trailing
        trailingAccessoryContainerView.translatesAutoresizingMaskIntoConstraints = false

        initializeConstraints()
    }

    required init?(coder: NSCoder) {
        owsFail("Not implemented!")
    }

    // MARK: -

    func initializeTrailingAccessoryViews(_ trailingAccessoryViews: [UIView]) {
        for trailingAccessoryView in trailingAccessoryViews {
            trailingAccessoryContainerView.addArrangedSubview(trailingAccessoryView)
            trailingAccessoryView.translatesAutoresizingMaskIntoConstraints = false
            trailingAccessoryView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        }
    }

    func configure(
        leadingAccessoryImage: UIImage,
        leadingAccessoryImageTintColor: UIColor,
        titleLabelText: String,
        progressLabelText: String?,
        trailingAccessoryView: UIView?,
    ) {
        leadingAccessoryImageView.image = leadingAccessoryImage
        leadingAccessoryImageView.tintColor = leadingAccessoryImageTintColor

        titleLabel.text = titleLabelText
        if let progressLabelText {
            progressLabel.text = progressLabelText
            progressLabel.isHidden = false
        } else {
            progressLabel.isHidden = true
        }

        for view in trailingAccessoryContainerView.arrangedSubviews {
            if view === trailingAccessoryView {
                view.isHidden = false
            } else {
                view.isHidden = true
            }
        }
    }

    // MARK: -

    private func initializeConstraints() {
        labelStackView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            leadingAccessoryImageView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            leadingAccessoryImageView.centerYAnchor.constraint(equalTo: labelStackView.centerYAnchor),
            leadingAccessoryImageView.heightAnchor.constraint(equalToConstant: 24),
            leadingAccessoryImageView.widthAnchor.constraint(equalToConstant: 24),

            labelStackView.leadingAnchor.constraint(equalTo: leadingAccessoryImageView.trailingAnchor, constant: 12),
            labelStackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            labelStackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            labelStackView.trailingAnchor.constraint(equalTo: trailingAccessoryContainerView.leadingAnchor, constant: -12),

            trailingAccessoryContainerView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            trailingAccessoryContainerView.centerYAnchor.constraint(equalTo: labelStackView.centerYAnchor),
        ])
    }
}

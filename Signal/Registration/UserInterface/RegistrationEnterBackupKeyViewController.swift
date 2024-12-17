//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

protocol RegistrationEnterBackupKeyPresenter: AnyObject {
    func next()
}

class RegistrationEnterBackupKeyViewController: OWSViewController, OWSNavigationChildController {
    private weak var presenter: RegistrationEnterBackupKeyPresenter?

    init(presenter: RegistrationEnterBackupKeyPresenter) {
        self.presenter = presenter
        super.init()

        navigationItem.rightBarButtonItem = canSubmit ? nextBarButton : nil

        self.view.backgroundColor = Theme.backgroundColor

        self.view.addSubview(titleLabel)
        self.view.addSubview(descriptionLabel)
        self.view.addSubview(textView)
        self.view.addSubview(noKeyButton)

        NSLayoutConstraint.activate([
            self.titleLabel.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.descriptionLabel.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 12),
            self.textView.topAnchor.constraint(equalTo: self.descriptionLabel.bottomAnchor, constant: 24),
            self.noKeyButton.topAnchor.constraint(equalTo: self.textView.bottomAnchor, constant: 24),

            self.titleLabel.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            self.titleLabel.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -12),

            self.descriptionLabel.leadingAnchor.constraint(equalTo: self.titleLabel.leadingAnchor),
            self.descriptionLabel.trailingAnchor.constraint(equalTo: self.titleLabel.trailingAnchor),

            self.textView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),

            self.noKeyButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)
        ])
    }

    // MARK: OWSNavigationChildController

    public var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }

    public var navbarBackgroundColorOverride: UIColor? { .clear }

    public var prefersNavigationBarHidden: Bool { true }

    // MARK: UI

    private lazy var textView: BackupCodeTextView = {
        let textView = BackupCodeTextView()
        textView.autocorrectionType = .no
        return textView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "REGISTRATION_ENTER_BACKUP_KEY_TITLE",
            comment: "Title for the screen that allows users to enter their backup key."
        )
        label.textAlignment = .center
        label.font = .dynamicTypeTitle1.semibold()
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "REGISTRATION_ENTER_BACKUP_KEY_DESCRIPTION",
            comment: "Description for the screen that allows users to enter their backup key."
        )
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var noKeyButton: UIButton = {
        let button = UIButton()
        button.setTitle(
            OWSLocalizedString(
                "REGISTRATION_NO_BACKUP_KEY_BUTTON_TITLE",
                comment: "Title of button to tap if you do not have a backup key during registration."
            ),
            for: .normal
        )
        button.titleLabel?.font = .dynamicTypeBody.bold()
        button.setTitleColor(UIColor.Signal.ultramarine, for: .normal)
        button.sizeToFit()
        button.addTarget(self, action: #selector(didTapNoKeyButton), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    @objc
    private func didTapNoKeyButton() {
        // TODO [Reg UI]: IOS-5448.
    }

    private lazy var nextBarButton = UIBarButtonItem(
        title: CommonStrings.nextButton,
        style: .done,
        target: self,
        action: #selector(didTapNext)
    )

    @objc
    private func didTapNext() {
        guard canSubmit else { return }
        textView.resignFirstResponder()
        self.presenter?.next()
    }

    private var canSubmit: Bool {
        let codeCharCount = textView.text.filter {
            $0.isNumber || $0.isLetter
        }.count

        let expectedCodeCharCount = BackupCodeTextView.Constants.totalChunks * BackupCodeTextView.Constants.chunkSize

        return codeCharCount == expectedCodeCharCount
    }
}

private class BackupCodeTextView: UITextView, UITextViewDelegate {
    fileprivate enum Constants {
        static let chunkSize = 4
        static let chunksPerRow = 4
        static let spacesBetweenChunks = 4
        static let totalChunks = 16
        static let insets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        static let font = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        static let lineSpacing = 10.0
        static let backgroundColor = UIColor.ows_gray02
    }

    convenience init() {
        self.init(frame: .zero, textContainer: nil)
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)

        self.backgroundColor = Constants.backgroundColor
        self.textContainerInset = Constants.insets
        self.textContainer.lineFragmentPadding = 0
        self.delegate = self
        self.isEditable = true
        self.isSelectable = true
        self.layer.cornerRadius = 10
        // TODO [Reg UI]: Add placeholder text. IOS-5451.

        // The font is taken care of by the attributed string, but setting
        // this here makes the cursor the right size to start with.
        let font = Constants.font
        self.font = font

        self.translatesAutoresizingMaskIntoConstraints = false

        // Any character will do because font is monospaced.
        let charSize = " ".size(withAttributes: [.font: Constants.font])

        let totalChars = (Constants.chunksPerRow * Constants.chunkSize) + (Constants.spacesBetweenChunks * (Constants.chunksPerRow-1))
        let horizontalEdgeInsetSpace = Constants.insets.left + Constants.insets.right
        let desiredWidth = (charSize.width * CGFloat(totalChars)).rounded(.up) + horizontalEdgeInsetSpace

        let heightPerChar = charSize.height
        let rows = Constants.totalChunks / Constants.chunksPerRow
        let heightFromRows = CGFloat(rows) * heightPerChar
        let heightFromLineSpacing = Constants.lineSpacing * (Double(rows) - 1)
        let height = (heightFromRows + Constants.insets.top + Constants.insets.bottom + heightFromLineSpacing).rounded(.up)

        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: desiredWidth),
            self.heightAnchor.constraint(equalToConstant: height)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let currentText = textView.text ?? ""
        let updatedText = (currentText as NSString).replacingCharacters(in: range, with: text)
        let filtered = updatedText.filter { $0.isNumber || $0.isLetter }
        let prefixed = filtered.prefix(Constants.totalChunks * Constants.chunkSize)
        let lowercased = prefixed.lowercased()
        let formatted = String(lowercased.formattedWithSpaces(every: Constants.chunkSize))

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = Constants.lineSpacing
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .font: Constants.font
        ]
        let attributedStr = NSAttributedString(string: formatted, attributes: attributes)
        textView.attributedText = attributedStr

        return false
    }
}

private extension String {
    func formattedWithSpaces(every n: Int, separator: String = "    ") -> String {
        guard n > 0 else { return self }
        return self.enumerated().map { $0.offset % n == 0 && $0.offset != 0 ? "\(separator)\($0.element)" : "\($0.element)" }.joined()
    }
}

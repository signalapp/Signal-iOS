//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class PaymentsViewPassphraseGridViewController: OWSTableViewController2 {

    private let passphrase: PaymentsPassphrase

    private weak var viewPassphraseDelegate: PaymentsViewPassphraseDelegate?

    private let bottomStack = UIStackView()

    open override var bottomFooter: UIView? { bottomStack }

    public required init(passphrase: PaymentsPassphrase,
                         viewPassphraseDelegate: PaymentsViewPassphraseDelegate) {
        self.passphrase = passphrase
        self.viewPassphraseDelegate = viewPassphraseDelegate

        super.init()

        self.shouldAvoidKeyboard = true
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_TITLE",
                                  comment: "Title for the 'view payments passphrase' view of the app settings.")

        buildBottomView()
        updateContents()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateContents()
    }

    private func buildBottomView() {
        let nextButton = OWSFlatButton.button(title: CommonStrings.nextButton,
                                              font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                              titleColor: .white,
                                              backgroundColor: .ows_accentBlue,
                                              target: self,
                                              selector: #selector(didTapNextButton))
        nextButton.autoSetHeightUsingFont()

        bottomStack.axis = .vertical
        bottomStack.alignment = .fill
        bottomStack.isLayoutMarginsRelativeArrangement = true
        let hMargin = 20 + OWSTableViewController2.cellHOuterMargin
        bottomStack.layoutMargins = UIEdgeInsets(top: 8, leading: hMargin, bottom: 0, trailing: hMargin)
        bottomStack.addArrangedSubviews([
            nextButton,
            UIView.spacer(withHeight: 8)
        ])
    }

    private func updateContents() {
        updateTableContents()
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.customHeaderView = buildHeader()
        section.customFooterView = buildFooter()

        let passphrase = self.passphrase
        section.add(OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()
            let passphraseGrid = PaymentsViewUtils.buildPassphraseGrid(passphrase: passphrase)
            cell.contentView.addSubview(passphraseGrid)
            passphraseGrid.autoPinEdgesToSuperviewMargins()
            return cell
        },
        actionBlock: nil))
        contents.addSection(section)

        self.contents = contents
    }

    private func buildHeader() -> UIView {
        let explanationLabel = UILabel()
        explanationLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_WORDS_EXPLANATION",
                                                  comment: "Header text for the 'review payments passphrase words' step in the 'view payments passphrase' settings.")
        explanationLabel.font = .ows_dynamicTypeBody2Clamped
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.textAlignment = .center
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping

        let topStack = UIStackView(arrangedSubviews: [
            explanationLabel
        ])
        topStack.axis = .vertical
        topStack.alignment = .center
        topStack.isLayoutMarginsRelativeArrangement = true
        let hMargin = 20 + OWSTableViewController2.cellHOuterMargin
        topStack.layoutMargins = UIEdgeInsets(top: 32, leading: hMargin, bottom: 40, trailing: hMargin)
        return topStack
    }

    private func buildFooter() -> UIView {
        let explanationLabel = UILabel()
        explanationLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_WORDS_FOOTER",
                                                  comment: "Footer text for the 'review payments passphrase words' step in the 'view payments passphrase' settings.")
        explanationLabel.font = .ows_dynamicTypeSubheadlineClamped
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.textAlignment = .center
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping

        let topStack = UIStackView(arrangedSubviews: [
            explanationLabel
        ])
        topStack.axis = .vertical
        topStack.alignment = .center
        topStack.isLayoutMarginsRelativeArrangement = true
        let hMargin = 20 + OWSTableViewController2.cellHOuterMargin
        topStack.layoutMargins = UIEdgeInsets(top: 16, leading: hMargin, bottom: 16, trailing: hMargin)
        return topStack
    }

    // MARK: - Events

    @objc
    func didTapNextButton() {
        guard let viewPassphraseDelegate = viewPassphraseDelegate else {
            dismiss(animated: false, completion: nil)
            return
        }
        let view = PaymentsViewPassphraseConfirmViewController(passphrase: passphrase,
                                                               viewPassphraseDelegate: viewPassphraseDelegate)
        navigationController?.pushViewController(view, animated: true)
    }
}

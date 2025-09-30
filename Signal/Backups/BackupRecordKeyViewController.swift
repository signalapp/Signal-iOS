//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class BackupRecordKeyViewController: HostingController<BackupRecordKeyView> {
    struct Option: OptionSet {
        let rawValue: Int

        /// Show a "continue" button in the view footer. Not compatible with
        /// `.showCreateNewKeyButton`.
        static let showContinueButton = Option(rawValue: 1 << 1)
        /// Show a "create new key" button in the view footer. Not compatible
        /// with `.showContinueButton`.
        static let showCreateNewKeyButton = Option(rawValue: 1 << 2)
    }

    enum AEPMode {
        /// The user's current AEP, which must only be viewed after device auth.
        case current(AccountEntropyPool, LocalDeviceAuthentication.AuthSuccess)
        /// A new candidate AEP.
        case newCandidate(AccountEntropyPool)

        fileprivate var aep: AccountEntropyPool {
            switch self {
            case .current(let aep, _): return aep
            case .newCandidate(let aep): return aep
            }
        }
    }

    private let onContinuePressedBlock: (BackupRecordKeyViewController) -> Void
    private let onCreateNewKeyPressedBlock: (BackupRecordKeyViewController) -> Void
    private let options: [Option]
    private let viewModel: BackupRecordKeyViewModel

    /// - Parameter onCreateNewKeyPressed
    /// Called when the user taps the "create new key" button. Only relevant if
    /// the `.showCreateNewKeyButton` option is passed.
    /// - Parameter onContinuePressed
    /// Called when the user taps the "continue" button. Only relevant if the
    /// `.showContinueButton` option is passed.
    init(
        aepMode: AEPMode,
        options: [Option],
        onCreateNewKeyPressed: @escaping (BackupRecordKeyViewController) -> Void = { _ in },
        onContinuePressed: @escaping (BackupRecordKeyViewController) -> Void = { _ in },
    ) {
        self.onContinuePressedBlock = onContinuePressed
        self.onCreateNewKeyPressedBlock = onCreateNewKeyPressed
        self.options = options
        self.viewModel = BackupRecordKeyViewModel(aep: aepMode.aep, options: options)

        super.init(wrappedView: BackupRecordKeyView(viewModel: viewModel))

        viewModel.actionsDelegate = self
        OWSTableViewController2.removeBackButtonText(viewController: self)
    }
}

extension BackupRecordKeyViewController: BackupRecordKeyViewModel.ActionsDelegate {
    fileprivate func copyToClipboard(_ aep: AccountEntropyPool) {
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: aep.displayString]],
            options: [.expirationDate: Date().addingTimeInterval(60)]
        )

        let toast = ToastController(text: OWSLocalizedString(
            "BACKUP_KEY_COPIED_MESSAGE_TOAST",
            comment: "Toast indicating that the user has copied their recovery key."
        ))
        toast.presentToastView(from: .bottom, of: view, inset: view.safeAreaInsets.bottom + 8)
    }

    fileprivate func onContinuePressed() {
        onContinuePressedBlock(self)
    }

    fileprivate func onCreateNewKeyPressed() {
        onCreateNewKeyPressedBlock(self)
    }
}

// MARK: -

private class BackupRecordKeyViewModel: ObservableObject {
    protocol ActionsDelegate: AnyObject {
        func copyToClipboard(_ aep: AccountEntropyPool)
        func onContinuePressed()
        func onCreateNewKeyPressed()
    }

    let aep: AccountEntropyPool
    let options: [BackupRecordKeyViewController.Option]

    weak var actionsDelegate: ActionsDelegate?

    init(aep: AccountEntropyPool, options: [BackupRecordKeyViewController.Option]) {
        self.aep = aep
        self.options = options
    }

    // MARK: -

    func copyToClipboard() {
        actionsDelegate?.copyToClipboard(aep)
    }

    func onContinuePressed() {
        actionsDelegate?.onContinuePressed()
    }

    func onCreateNewKeyPressed() {
        actionsDelegate?.onCreateNewKeyPressed()
    }
}

// MARK: -

struct BackupRecordKeyView: View {
    fileprivate let viewModel: BackupRecordKeyViewModel

    var body: some View {
        ScrollableContentPinnedFooterView {
            VStack {
                Spacer().frame(height: 20)

                Image(.backupsLock)
                    .frame(width: 80, height: 80)

                Spacer().frame(height: 16)

                Text(OWSLocalizedString(
                    "BACKUP_RECORD_KEY_TITLE",
                    comment: "Title for a view allowing users to record their 'Recovery Key'."
                ))
                .font(.title)
                .fontWeight(.semibold)
                .foregroundStyle(Color.Signal.label)
                .padding(.horizontal, 24) // Extra

                Spacer().frame(height: 12)

                Text(OWSLocalizedString(
                    "BACKUP_RECORD_KEY_SUBTITLE",
                    comment: "Subtitle for a view allowing users to record their 'Recovery Key'."
                ))
                .font(.body)
                .foregroundStyle(Color.Signal.secondaryLabel)
                .padding(.horizontal, 28) // Extra

                Spacer().frame(height: 32)

                DisplayAccountEntropyPoolView(aep: viewModel.aep)

                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 12)
        } pinnedFooter: {
            Button {
                viewModel.copyToClipboard()
            } label: {
                Text(OWSLocalizedString(
                    "BACKUP_RECORD_KEY_COPY_TO_CLIPBOARD_BUTTON_TITLE",
                    comment: "Title for a button allowing users to copy their 'Recovery Key' to the clipboard."
                ))
                .fontWeight(.medium)
                .font(.footnote)
            }
            .foregroundStyle(Color.Signal.label)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(Color.Signal.secondaryFill)
            }

            if viewModel.options.contains(.showCreateNewKeyButton) {
                Spacer().frame(height: 32)

                Button {
                    viewModel.onCreateNewKeyPressed()
                } label: {
                    Text(OWSLocalizedString(
                        "BACKUP_RECORD_KEY_CREATE_NEW_KEY_BUTTON_TITLE",
                        comment: "Title for a button allowing users to create a new 'Recovery Key'."
                    ))
                    .foregroundStyle(Color.Signal.ultramarine)
                    .font(.headline)
                }
            }

            if viewModel.options.contains(.showContinueButton) {
                Spacer().frame(height: 32)

                Button {
                    viewModel.onContinuePressed()
                } label: {
                    Text(CommonStrings.continueButton)
                        .foregroundStyle(.white)
                        .font(.headline)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color.Signal.ultramarine)
                }
                .buttonStyle(.plain)
                .cornerRadius(12)
                .padding(.horizontal, 40)
            }
        }
        .multilineTextAlignment(.center)
        .background(Color.Signal.groupedBackground)
    }
}

// MARK: -

private struct DisplayAccountEntropyPoolView: View {
    private enum Constants {
        static let charsPerGroup = 4
        static let charGroupsPerLine = 4
        static let spacesTwixtGroups = 4

        private static let formattingPrecondition: Void = {
            let charsPerLine = charsPerGroup * charGroupsPerLine
            owsPrecondition(AccountEntropyPool.Constants.byteLength % charsPerLine == 0)
        }()
    }

    let aep: AccountEntropyPool

    var body: some View {
        Text(stylizedAEPText)
            .lineSpacing(18)
            .font(.body.monospaced())
            .padding(.vertical, 18)
            .padding(.horizontal, 36)
            .background(Color.Signal.secondaryGroupedBackground)
            .foregroundStyle(Color.Signal.label)
            .cornerRadius(16)
    }

    /// Split the AEP into char groups, themselves split across multiple lines.
    ///
    /// - Important
    /// This does index-based accesses, and will crash if the (hardcoded) length
    /// of an AEP changes. `Constants.formattingPrecondition` should alert in
    /// that case.
    private var stylizedAEPText: String {
        let aep = aep.displayString

        let charGroups: [String] = stride(from: 0, to: aep.count, by: Constants.charsPerGroup).map {
            let startIndex = aep.index(aep.startIndex, offsetBy: $0)
            let endIndex = aep.index(startIndex, offsetBy: Constants.charsPerGroup)

            return String(aep[startIndex..<endIndex])
        }

        let charGroupsByLine: [[String]] = stride(from: 0, to: charGroups.count, by: Constants.charGroupsPerLine).map {
            let startIndex = charGroups.index(charGroups.startIndex, offsetBy: $0)
            let endIndex = charGroups.index(startIndex, offsetBy: Constants.charGroupsPerLine)

            return Array(charGroups[startIndex..<endIndex])
        }

        let lines: [String] = charGroupsByLine.map { charGroups in
            return charGroups.joined(separator: String(repeating: " ", count: Constants.spacesTwixtGroups))
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: -

#if DEBUG

private extension BackupRecordKeyViewModel {
    static func forPreview(
        options: [BackupRecordKeyViewController.Option],
    ) -> BackupRecordKeyViewModel {
        class PreviewActionsDelegate: ActionsDelegate {
            func copyToClipboard(_ aep: AccountEntropyPool) { print("Copying \(aep.displayString) to clipboard...!") }
            func onContinuePressed() { print("Completing...!") }
            func onCreateNewKeyPressed() { print("Creating new key...!") }
        }

        let viewModel = BackupRecordKeyViewModel(
            aep: AccountEntropyPool(),
            options: options,
        )
        let actionsDelegate = PreviewActionsDelegate()
        ObjectRetainer.retainObject(actionsDelegate, forLifetimeOf: viewModel)
        return viewModel
    }
}

#Preview("CreateNewKey") {
    NavigationView {
        BackupRecordKeyView(viewModel: .forPreview(options: [.showCreateNewKeyButton]))
    }
}

#Preview("ContinueButton") {
    NavigationView {
        BackupRecordKeyView(viewModel: .forPreview(options: [.showContinueButton]))
    }
}

#endif

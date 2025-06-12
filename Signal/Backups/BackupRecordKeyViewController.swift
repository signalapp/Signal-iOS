//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class BackupRecordKeyViewController: HostingController<BackupRecordKeyView> {
    private let onCompletion: (BackupRecordKeyViewController) -> Void
    private let viewModel: BackupRecordKeyViewModel
    private let isOnboardingFlow: Bool

    init(
        aep: AccountEntropyPool,
        isOnboardingFlow: Bool,
        onCompletion: @escaping (BackupRecordKeyViewController) -> Void,
    ) {
        self.onCompletion = onCompletion
        self.isOnboardingFlow = isOnboardingFlow
        self.viewModel = BackupRecordKeyViewModel(aep: aep, isOnboardingFlow: isOnboardingFlow)

        super.init(wrappedView: BackupRecordKeyView(viewModel: viewModel))

        viewModel.actionsDelegate = self
    }
}

extension BackupRecordKeyViewController: BackupRecordKeyViewModel.ActionsDelegate {
    func copyToClipboard(_ aep: AccountEntropyPool) {
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: aep.rawData]],
            options: [.expirationDate: Date().addingTimeInterval(60)]
        )
    }

    func complete() {
        onCompletion(self)
    }
}

// MARK: -

private class BackupRecordKeyViewModel: ObservableObject {
    protocol ActionsDelegate: AnyObject {
        func copyToClipboard(_ aep: AccountEntropyPool)
        func complete()
    }

    weak var actionsDelegate: ActionsDelegate?
    let aep: AccountEntropyPool
    let isOnboardingFlow: Bool

    init(aep: AccountEntropyPool, isOnboardingFlow: Bool) {
        self.aep = aep
        self.isOnboardingFlow = isOnboardingFlow
    }

    func copyToClipboard() {
        actionsDelegate?.copyToClipboard(aep)
    }

    func complete() {
        actionsDelegate?.complete()
    }
}

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
                    comment: "Title for a view allowing users to record their 'Backup Key'."
                ))
                .font(.title)
                .fontWeight(.semibold)
                .foregroundStyle(Color.Signal.label)
                .padding(.horizontal, 24) // Extra

                Spacer().frame(height: 12)

                Text(OWSLocalizedString(
                    "BACKUP_RECORD_KEY_SUBTITLE",
                    comment: "Subtitle for a view allowing users to record their 'Backup Key'."
                ))
                .font(.body)
                .foregroundStyle(Color.Signal.secondaryLabel)
                .padding(.horizontal, 28) // Extra

                Spacer().frame(height: 32)

                DisplayAccountEntropyPoolView(aep: viewModel.aep)

                Spacer().frame(height: 32)

                Button {
                    viewModel.copyToClipboard()
                } label: {
                    Text(OWSLocalizedString(
                        "BACKUP_RECORD_KEY_COPY_TO_CLIPBOARD_BUTTON_TITLE",
                        comment: "Title for a button allowing users to copy their 'Backup Key' to the clipboard."
                    ))
                    .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(Color.Signal.secondaryFill)
                }

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 12)
        } pinnedFooter: {
            // Only add "continue" button if we're in the onboarding flow.
            if viewModel.isOnboardingFlow {
                Button {
                    viewModel.complete()
                } label: {
                    Text(CommonStrings.continueButton)
                        .foregroundStyle(.white)
                        .font(.headline)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .background(Color.Signal.ultramarine)
                .cornerRadius(12)
                .padding(.horizontal, 40)
            }
        }
        .multilineTextAlignment(.center)
        .background(Color.Signal.groupedBackground)
        .navigationBarBackButtonHidden(!viewModel.isOnboardingFlow)
        .navigationBarItems(leading: viewModel.isOnboardingFlow ? nil : doneButton)
    }

    private var doneButton: some View {
        Button(action: {
            viewModel.complete()
        }) {
            Text(OWSLocalizedString("BUTTON_DONE", comment: "Label for generic done button."))
                .buttonStyle(.plain)
                .foregroundStyle(Color.Signal.label)
        }
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
        let aep = aep.rawData

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
    static func forPreview() -> BackupRecordKeyViewModel {
        class PreviewActionsDelegate: ActionsDelegate {
            func copyToClipboard(_ aep: AccountEntropyPool) {
                print("Copying \(aep.rawData) to clipboard...!")
            }

            func complete() {
                print("Continuing...!")
            }
        }

        let viewModel = BackupRecordKeyViewModel(aep: AccountEntropyPool(), isOnboardingFlow: true)
        let actionsDelegate = PreviewActionsDelegate()
        ObjectRetainer.retainObject(actionsDelegate, forLifetimeOf: viewModel)
        return viewModel
    }
}

#Preview {
    BackupRecordKeyView(viewModel: .forPreview())
}

#endif

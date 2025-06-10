//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class BackupRecordKeyViewController: HostingController<BackupRecordKeyView> {
    init(
        aep: AccountEntropyPool,
        onContinue: @escaping () -> Void
    ) {
        super.init(wrappedView: BackupRecordKeyView(
            aep: aep,
            onContinue: onContinue,
            onCopyToClipboard: {
                UIPasteboard.general.setItems(
                    [[UIPasteboard.typeAutomatic: aep.rawData]],
                    options: [.expirationDate: Date().addingTimeInterval(60)]
                )
            }
        ))
    }
}

// MARK: -

struct BackupRecordKeyView: View {
    fileprivate let aep: AccountEntropyPool
    fileprivate let onContinue: () -> Void
    fileprivate let onCopyToClipboard: () -> Void

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

                DisplayAccountEntropyPoolView(aep: aep)

                Spacer().frame(height: 32)

                Button {
                    onCopyToClipboard()
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
            Button {
                onContinue()
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

#Preview {
    let aep = AccountEntropyPool()

    BackupRecordKeyView(
        aep: aep,
        onContinue: {
            print("Continuing...!")
        },
        onCopyToClipboard: {
            print("Copying \(aep.rawData) to clipboard...!")
        }
    )
}

#endif

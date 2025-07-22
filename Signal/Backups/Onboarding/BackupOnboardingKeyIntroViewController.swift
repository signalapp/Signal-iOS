//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class BackupOnboardingKeyIntroViewController: HostingController<BackupOnboardingKeyIntroView> {
    private let onDeviceAuthSucceeded: () -> Void
    private let viewModel: BackupsOnboardingKeyIntroViewModel

    init(onDeviceAuthSucceeded: @escaping () -> Void) {
        self.onDeviceAuthSucceeded = onDeviceAuthSucceeded
        self.viewModel = BackupsOnboardingKeyIntroViewModel()

        super.init(wrappedView: BackupOnboardingKeyIntroView(viewModel: viewModel))

        viewModel.actionsDelegate = self
    }
}

// MARK: -

extension BackupOnboardingKeyIntroViewController: BackupsOnboardingKeyIntroViewModel.ActionsDelegate {
    fileprivate func onContinue() {
        Task {
            if await LocalDeviceAuthentication().performBiometricAuth() {
                onDeviceAuthSucceeded()
            }
        }
    }
}

// MARK: -

private class BackupsOnboardingKeyIntroViewModel {
    protocol ActionsDelegate: AnyObject {
        func onContinue()
    }

    weak var actionsDelegate: ActionsDelegate?

    func onContinue() {
        actionsDelegate?.onContinue()
    }
}

struct BackupOnboardingKeyIntroView: View {
    fileprivate let viewModel: BackupsOnboardingKeyIntroViewModel

    var body: some View {
        ScrollableContentPinnedFooterView {
            VStack {
                Spacer().frame(height: 20)

                Image(.backupsKey)
                    .frame(width: 80, height: 80)

                Spacer().frame(height: 16)

                Text(OWSLocalizedString(
                    "BACKUP_ONBOARDING_KEY_INTRO_TITLE",
                    comment: "Title for a view introducing the 'Backup Key' during an onboarding flow."
                ))
                .font(.title)
                .fontWeight(.semibold)
                .foregroundStyle(Color.Signal.label)

                Spacer().frame(height: 12)

                Text(OWSLocalizedString(
                    "BACKUP_ONBOARDING_KEY_INTRO_SUBTITLE",
                    comment: "Subtitle for a view introducing the 'Backup Key' during an onboarding flow."
                ))
                .font(.body)
                .foregroundStyle(Color.Signal.secondaryLabel)
            }
            .padding(.horizontal, 48)
        } pinnedFooter: {
            Button {
                viewModel.onContinue()
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

#if DEBUG

extension BackupsOnboardingKeyIntroViewModel {
    static func forPreview() -> BackupsOnboardingKeyIntroViewModel {
        class PreviewActionsDelegate: ActionsDelegate {
            func onContinue() { print("Continuing...!") }
        }

        let viewModel = BackupsOnboardingKeyIntroViewModel()
        let actionsDelegate = PreviewActionsDelegate()
        viewModel.actionsDelegate = actionsDelegate
        ObjectRetainer.retainObject(actionsDelegate, forLifetimeOf: viewModel)

        return viewModel
    }
}

#Preview {
    BackupOnboardingKeyIntroView(viewModel: .forPreview())
}

#endif

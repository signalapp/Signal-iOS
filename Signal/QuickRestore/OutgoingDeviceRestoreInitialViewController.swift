//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import SwiftUI

protocol OutgoingDeviceRestoreInitialPresenter {
    func didTapTransfer() async
}

class OutgoingDeviceRestoreIntialViewController: HostingController<OutgoingDeviceRestoreInitialView> {
    init(presenter: OutgoingDeviceRestoreInitialPresenter) {
        super.init(wrappedView: OutgoingDeviceRestoreInitialView(presenter: presenter))
        self.modalPresentationStyle = .overFullScreen
        self.title = OWSLocalizedString(
            "OUTGOING_DEVICE_RESTORE_INITIAL_VIEW_TITLE",
            comment: "Title text describing the outgoing transfer.",
        )
        self.navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
        view.backgroundColor = UIColor.Signal.secondaryBackground
        OWSTableViewController2.removeBackButtonText(viewController: self)
    }
}

struct OutgoingDeviceRestoreInitialView: View {
    private let presenter: OutgoingDeviceRestoreInitialPresenter
    init(presenter: OutgoingDeviceRestoreInitialPresenter) {
        self.presenter = presenter
    }

    var body: some View {
        SignalList {
            SignalSection {
                VStack(alignment: .center, spacing: 24) {
                    Image("transfer_account")

                    Text(OWSLocalizedString(
                        "OUTGOING_DEVICE_RESTORE_INITIAL_VIEW_BODY",
                        comment: "Body text describing the outgoing transfer.",
                    ))
                    .appendLink(CommonStrings.learnMore) {
                        UIApplication.shared.open(URL(string: "TODO: link to documentation")!)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                    .tint(Color.Signal.label)

                    Button(OWSLocalizedString(
                        "OUTGOING_DEVICE_RESTORE_INITIAL_VIEW_CONFIRM_ACTION",
                        comment: "Action button to begin account transfer.",
                    )) {
                        Task {
                            await self.presenter.didTapTransfer()
                        }
                    }
                    .buttonStyle(Registration.UI.LargePrimaryButtonStyle())
                }.padding([.top, .bottom], 12)
            }
            footer: {
                let footerString = OWSLocalizedString(
                    "OUTGOING_DEVICE_RESTORE_INITIAL_VIEW_FOOTER",
                    comment: "Body text describing the outgoing transfer.",
                )
                Text("\(SignalSymbol.lock.text(dynamicTypeBaseSize: 14)) \(footerString)")
                    .font(.footnote)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                    .padding([.top, .bottom], 12)
            }
        }
        .scrollBounceBehaviorIfAvailable(.basedOnSize)
        .multilineTextAlignment(.center)
    }
}

// MARK: Previews

#if DEBUG
struct PreviewOutgoingDeviceRestoreIntialPresenter: OutgoingDeviceRestoreInitialPresenter {
    func didTapTransfer() async {
        print("didTapTransfer()")
    }
}

@available(iOS 17, *)
#Preview {
    OWSNavigationController(
        rootViewController: OutgoingDeviceRestoreIntialViewController(
            presenter: PreviewOutgoingDeviceRestoreIntialPresenter(),
        ),
    )
}
#endif

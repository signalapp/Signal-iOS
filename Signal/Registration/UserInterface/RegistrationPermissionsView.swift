//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

@MainActor
protocol RegistrationPermissionsPresenter {
    func requestPermissions() async
}

final class RegistrationPermissionsViewController: UIHostingController<RegistrationPermissionsView> {
    init(presenter: any RegistrationPermissionsPresenter) {
        super.init(rootView: RegistrationPermissionsView(presenter: presenter))
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct RegistrationPermissionsView: View {
    var presenter: any RegistrationPermissionsPresenter
    @State private var requestPermissions: RequestPermissionsTask?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AccessibleLayoutMetric private var headerPadding = 16
    @AccessibleLayoutMetric private var headerSpacing = 12
    @AccessibleLayoutMetric(scale: 0.5) private var sectionSpacing = 64

    var body: some View {
        VStack {
            VStack(spacing: headerSpacing) {
                Text(OWSLocalizedString("ONBOARDING_PERMISSIONS_TITLE", comment: "Title of the 'onboarding permissions' view."))
                    .font(.title.weight(.semibold))
                    .lineLimit(1)
                Text(OWSLocalizedString("ONBOARDING_PERMISSIONS_PREAMBLE", comment: "Preamble of the 'onboarding permissions' view."))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, headerPadding)

            ScrollView {
                VStack {
                    Spacer(minLength: sectionSpacing)
                        .frame(maxHeight: $sectionSpacing.rawValue)
                        .layoutPriority(-1)

                    VStack(alignment: .leading, spacing: 32) {
                        PermissionDescription {
                            Text(OWSLocalizedString("ONBOARDING_PERMISSIONS_NOTIFICATIONS_TITLE", comment: "Title introducing the 'Notifications' permission in the 'onboarding permissions' view."))
                        } description: {
                            Text(OWSLocalizedString("ONBOARDING_PERMISSIONS_NOTIFICATIONS_DESCRIPTION", comment: "Description of the 'Notifications' permission in the 'onboarding permissions' view."))
                        } icon: {
                            PermissionIcon(.bellRing)
                        }

                        PermissionDescription {
                            Text(OWSLocalizedString("ONBOARDING_PERMISSIONS_CONTACTS_TITLE", comment: "Title introducing the 'Contacts' permission in the 'onboarding permissions' view."))
                        } description: {
                            Text(OWSLocalizedString("ONBOARDING_PERMISSIONS_CONTACTS_DESCRIPTION", comment: "Description of the 'Contacts' permission in the 'onboarding permissions' view."))
                        } icon: {
                            PermissionIcon(.personCircleLarge)
                        }
                    }

                    Spacer(minLength: sectionSpacing)
                        .layoutPriority(-1)

                    Button(CommonStrings.continueButton) {
                        requestPermissions = RequestPermissionsTask(presenter: presenter)
                    }
                    .buttonStyle(ContinueButtonStyle())
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .frame(maxWidth: 400)
                }
                .padding(EdgeInsets(.layoutMarginsForRegistration(UIUserInterfaceSizeClass(horizontalSizeClass))))
            }
            .scrollBounceBehaviorIfAvailable(.basedOnSize)
        }
        .foregroundStyle(Color.Signal.label, Color.Signal.secondaryLabel, Color.Signal.tertiaryLabel)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .minimumScaleFactor(0.9)
        .navigationBarBackButtonHidden()
        .task($requestPermissions.animation())
        // FIXME: Forcing light mode for consistency with the rest of registration
        .background(Color.Signal.background)
        .environment(\.colorScheme, .light)
    }
}

private extension RegistrationPermissionsView {
    struct ContinueButtonStyle: PrimitiveButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            Button(action: configuration.trigger) {
                HStack {
                    Spacer()
                    configuration.label
                        .colorScheme(.dark)
                        .font(.headline)
                    Spacer()
                }
                .frame(minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    struct PermissionDescription<Icon: View, Title: View, Description: View>: View {
        var icon: Icon
        var title: Title
        var description: Description

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        init(@ViewBuilder title: () -> Title, @ViewBuilder description: () -> Description, @ViewBuilder icon: () -> Icon) {
            self.title = title()
            self.description = description()
            self.icon = icon()
        }

        var body: some View {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 16) {
                        icon
                            .frame(width: 36)
                        title
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                    }
                    description
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    icon
                    VStack(alignment: .leading, spacing: 4) {
                        title
                            .font(.headline)
                            .lineLimit(1)
                        description
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                    }
                    Spacer()
                }
            }
        }
    }

    struct PermissionIcon: View {
        var resource: ImageResource

        init(_ resource: ImageResource) {
            self.resource = resource
        }

        var body: some View {
            Image(resource)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 48)
        }
    }

    struct RequestPermissionsTask: AsyncViewTask {
        let id = UUID()
        let presenter: any RegistrationPermissionsPresenter

        func perform() async {
            await presenter.requestPermissions()
        }
    }
}

#if DEBUG
private struct PreviewPermissionsPresenter: RegistrationPermissionsPresenter {
    func requestPermissions() async {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
    }
}

#Preview {
    VStack {
        Color.clear.frame(height: 44)
        RegistrationPermissionsView(presenter: PreviewPermissionsPresenter())
    }
}
#endif

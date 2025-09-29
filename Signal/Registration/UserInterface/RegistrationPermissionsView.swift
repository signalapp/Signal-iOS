//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

@MainActor
protocol RegistrationPermissionsPresenter: AnyObject {
    func requestPermissions() async
}

struct RegistrationPermissionsView: View {
    var requestingContactsAuthorization: Bool
    var permissionTask: (() async -> Void)

    @State private var hasAppeared = (notifications: false, contacts: false)
    @State private var requestPermissions: RequestPermissionsTask?

    @Environment(\.appearanceTransitionState) private var appearanceTransitionState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @AccessibleLayoutMetric private var headerPadding = 16
    @AccessibleLayoutMetric private var headerSpacing = 12
    @AccessibleLayoutMetric(scale: 0.5) private var sectionSpacing = 64

    private var isCompactLayout: Bool {
        horizontalSizeClass == .compact || verticalSizeClass == .compact
    }

    private var layoutMargins: EdgeInsets {
        if isCompactLayout {
            EdgeInsets(.layoutMarginsForRegistration(UIUserInterfaceSizeClass(horizontalSizeClass)))
        } else {
            EdgeInsets()
        }
    }

    var body: some View {
        VStack {
            VStack(spacing: headerSpacing) {
                if requestingContactsAuthorization {
                    Color.clear.frame(height: 32)
                }

                Text(OWSLocalizedString("ONBOARDING_PERMISSIONS_TITLE", comment: "Title of the 'onboarding permissions' view."))
                    .font(.title.weight(.semibold))
                    .lineLimit(1)
                Text(OWSLocalizedString("ONBOARDING_PERMISSIONS_PREAMBLE", comment: "Preamble of the 'onboarding permissions' view."))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, headerPadding)

            ScrollableWhenCompact {
                VStack {
                    Spacer(minLength: sectionSpacing)
                        .frame(maxHeight: $sectionSpacing.rawValue)
                        .layoutPriority(-1)

                    ZStack(alignment: .topLeading) {
                        // Make sure the full width is laid out whether
                        // or not the individual views have appeared.
                        VStack(alignment: .leading, spacing: 32) {
                            notificationsPermissionView

                            if requestingContactsAuthorization {
                                contactsPermissionView
                            }
                        }
                        .hidden()

                        // Animate them in one-by-one.
                        VStack(alignment: .leading, spacing: 32) {
                            Group {
                                if hasAppeared.notifications {
                                    notificationsPermissionView
                                }

                                if requestingContactsAuthorization && hasAppeared.contacts {
                                    contactsPermissionView
                                }
                            }
                            .transition(.offset(x: 0, y: -20).combined(with: .opacity))
                        }
                    }
                    // Expand to available width when compact, otherwise horizontally center.
                    .frame(maxWidth: isCompactLayout ? .infinity : nil, alignment: .leading)

                    Spacer(minLength: sectionSpacing)
                        .layoutPriority(-1)

                    Button(CommonStrings.continueButton) {
                        requestPermissions = RequestPermissionsTask(task: {
                            await permissionTask()
                        })
                    }
                    .buttonStyle(Registration.UI.FilledButtonStyle())
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .frame(maxWidth: 400)
                }
                .padding(layoutMargins)
            }
        }
        .onChange(of: appearanceTransitionState) { newValue in
            if newValue == .finished {
                let duration = 0.75
                let spring = Animation.spring(duration: duration)
                withAnimation(spring) {
                    hasAppeared.notifications = true
                }
                if requestingContactsAuthorization {
                    withAnimation(spring.delay(duration)) {
                        hasAppeared.contacts = true
                    }
                }
            }
        }
        .foregroundStyle(Color.Signal.label, Color.Signal.secondaryLabel, Color.Signal.tertiaryLabel)
        // Use larger text size on iPad.
        .transformEnvironment(\.dynamicTypeSize) { dynamicTypeSize in
            if !isCompactLayout, dynamicTypeSize < .xLarge {
                dynamicTypeSize = .xLarge
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .minimumScaleFactor(0.9)
        .navigationBarBackButtonHidden()
        .task($requestPermissions.animation())
    }

    private var notificationsPermissionView: some View {
        PermissionDescription {
            Text(OWSLocalizedString("ONBOARDING_PERMISSIONS_NOTIFICATIONS_TITLE", comment: "Title introducing the 'Notifications' permission in the 'onboarding permissions' view."))
        } description: {
            Text(OWSLocalizedString("ONBOARDING_PERMISSIONS_NOTIFICATIONS_DESCRIPTION", comment: "Description of the 'Notifications' permission in the 'onboarding permissions' view."))
        } icon: {
            PermissionIcon(.bellRing)
        }
    }

    private var contactsPermissionView: some View {
        PermissionDescription {
            Text(OWSLocalizedString("ONBOARDING_PERMISSIONS_CONTACTS_TITLE", comment: "Title introducing the 'Contacts' permission in the 'onboarding permissions' view."))
        } description: {
            Text(OWSLocalizedString("ONBOARDING_PERMISSIONS_CONTACTS_DESCRIPTION", comment: "Description of the 'Contacts' permission in the 'onboarding permissions' view."))
        } icon: {
            PermissionIcon(.personCircleLarge)
        }
    }
}

private extension RegistrationPermissionsView {
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
        let task: (() async -> Void)

        func perform() async {
            await task()
        }
    }
}

final class RegistrationPermissionsViewController: OWSViewController, OWSNavigationChildController {
    let requestingContactsAuthorization: Bool
    weak var presenter: (any RegistrationPermissionsPresenter)?

    var prefersNavigationBarHidden: Bool { true }

    init(requestingContactsAuthorization: Bool, presenter: any RegistrationPermissionsPresenter) {
        self.requestingContactsAuthorization = requestingContactsAuthorization
        self.presenter = presenter
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.Signal.background

        let hostingController = HostingController(
            wrappedView: RegistrationPermissionsView(
                requestingContactsAuthorization: requestingContactsAuthorization,
                permissionTask: { [weak self] in
                    await self?.presenter?.requestPermissions()
                }
            )
        )
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.autoPinEdgesToSuperviewEdges()
        hostingController.didMove(toParent: self)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#if DEBUG
final private class PreviewPermissionsPresenter: RegistrationPermissionsPresenter {
    func requestPermissions() async {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
    }
}

private let presenter = PreviewPermissionsPresenter()
@available(iOS 17, *)
#Preview {
    NavigationPreviewController(
        animateFirstAppearance: true,
        viewController: RegistrationPermissionsViewController(
            requestingContactsAuthorization: true,
            presenter: presenter
        )
    )
}
#endif

//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI
import SignalUI
import SignalRingRTC
import LibSignalClient
import SignalServiceKit

private typealias ApprovalRequest = CallLinkApprovalRequest

// MARK: - ApprovalRequestView

private struct ApprovalRequestView: View {
    enum Requests {
        case single(ApprovalRequest)
        case many(
            topRequest: ApprovalRequest,
            amountMore: Int,
            didTapMore: () -> Void
        )
    }

    var requests: Requests
    var openProfileDetails: () -> Void
    var didApprove: () -> Void
    var didDeny: () -> Void

    private var request: ApprovalRequest {
        switch requests {
        case let .single(approvalRequest):
            approvalRequest
        case let .many(topRequest, _, _):
            topRequest
        }
    }

    // MARK: Body

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                self.profileDetailsButton {
                    AvatarView(
                        dataSource: .address(self.request.address),
                        sizeClass: .fortyEight,
                        localUserDisplayMode: .asLocalUser,
                        badged: true
                    )
                }

                VStack(alignment: .leading) {
                    self.profileDetailsButton {
                        HStack {
                            Text("\(self.request.name)")
                                .lineLimit(1)
                            Text("\(Image(systemName: "chevron.forward"))")
                            // Per design, we want a new chevron that fades
                            // in/out with the new name instead of the same one
                            // sliding around as the name length changes.
                                .id(self.request.name)
                        }
                        .font(.body.bold())
                    }

                    self.profileDetailsButton {
                        Text(
                            OWSLocalizedString(
                                "CALL_LINK_JOIN_REQUEST_PROMPT",
                                comment: "Tappable label that appears below a user's name on a toast when they request to join a call link."
                            )
                        )
                        .multilineTextAlignment(.leading)
                        .font(.subheadline)
                    }
                }

                Spacer()

                HStack(spacing: 20) {
                    ActionButton(action: self.didDeny, color: .red, systemImage: "xmark")
                    ActionButton(action: self.didApprove, color: .green, systemImage: "checkmark")
                }
            }
            .padding(12)

            switch requests {
            case .single:
                EmptyView()
            case let .many(_, amountMore, action):
                MoreRequestsView(amountMore: amountMore, action: action)
            }
        }
        .foregroundColor(.white)
        .background(.regularMaterial)
        .environment(\.colorScheme, .dark)
        .cornerRadius(10)
    }

    // MARK: Helper views

    private func profileDetailsButton(label: () -> some View) -> some View {
        Button(action: self.openProfileDetails, label: label)
    }

    struct ActionButton: View {
        var action: () -> Void
        var color: Color
        var systemImage: String

        var body: some View {
            Button(action: self.action) {
                Circle()
                    .frame(width: 36, height: 36)
                    .foregroundColor(self.color)
                    .overlay {
                        Image(systemName: self.systemImage)
                            .resizable()
                            .font(.body.bold())
                            .padding(11)
                    }
            }
        }
    }

    struct MoreRequestsView: View {
        var amountMore: Int
        var action: () -> Void

        var body: some View {
            Button(action: self.action) {
                Group {
                    if #available(iOS 16.0, *) {
                        Text(CallStrings.callLinkMoreRequests(count: self.amountMore))
                            .contentTransition(.numericText())
                    } else {
                        Text(CallStrings.callLinkMoreRequests(count: self.amountMore))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(Color(.ows_gray65))
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            .environment(\.colorScheme, .dark)
        }
    }
}

// MARK: - ApprovalRequestStack

struct ApprovalRequestStack: View {
    typealias ApprovalRequest = CallLinkApprovalRequest

    @ObservedObject var viewModel: CallLinkApprovalViewModel

    var didTapMore: ([ApprovalRequest]) -> Void
    var didChangeHeight: (CGFloat) -> Void

    private var cappedRequests: [ApprovalRequest] {
        if self.viewModel.requests.count > 2 {
            Array(self.viewModel.requests.prefix(1))
        } else {
            self.viewModel.requests
        }
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            let displayedRequests = self.cappedRequests

            ForEach(displayedRequests) { request in
                let isTopOfStack = displayedRequests.count == 2 && request == displayedRequests.first
                let isBottomOfStack = displayedRequests.count == 2 && request == displayedRequests.last
                let isOnlyRequest = self.viewModel.requests.count == 1
                let requests: ApprovalRequestView.Requests =
                if self.viewModel.requests.count <= 2 {
                    .single(request)
                } else {
                    .many(
                        topRequest: request,
                        amountMore: self.viewModel.requests.count - 1,
                        didTapMore: {
                            self.didTapMore(self.viewModel.requests)
                        }
                    )
                }

                ApprovalRequestView(
                    requests: requests,
                    openProfileDetails: { self.viewModel.performRequestAction.send((.viewDetails, request)) },
                    didApprove: { self.viewModel.performRequestAction.send((.approve, request)) },
                    didDeny: { self.viewModel.performRequestAction.send((.deny, request)) }
                )
                .zIndex({
                    if isTopOfStack {
                        10
                    } else if isOnlyRequest {
                        -10
                    } else {
                        0
                    }
                }())
                .transition(.asymmetric(
                    insertion: isOnlyRequest ? .offset(y: 12).combined(with: .opacity) : .offset(y: -10).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                .padding(.bottom, isTopOfStack ? 12 : 0)
                .scaleEffect(isBottomOfStack ? .init(width: 0.95, height: 0.95) : .init(width: 1, height: 1), anchor: .bottom)
            }
        }
        .background {
            GeometryReader { geometry in
                EmptyView()
                    .onAppear {
                        self.didChangeHeight(geometry.size.height)
                    }
                    .onChange(of: geometry.size.height) { newValue in
                        self.didChangeHeight(newValue)
                    }
            }
        }
    }
}

// MARK: Preview

#if DEBUG

private extension ApprovalRequest {
    static let candice = ApprovalRequest(aci: .init(fromUUID: UUID()), name: "Candice")
    static let kai = ApprovalRequest(aci: .init(fromUUID: UUID()), name: "Kai really long first name")
    static let gerte = ApprovalRequest(aci: .init(fromUUID: UUID()), name: "Gerte")
    static let sam = ApprovalRequest(aci: .init(fromUUID: UUID()), name: "Sam")
}

private struct PreviewView: View {
    static let startingRequests: [ApprovalRequest] = [
        .candice,
        .kai,
    ]

    @StateObject private var viewModel = CallLinkApprovalViewModel()
    private var requests: [ApprovalRequest] { viewModel.requests }
    @State private var height: CGFloat = 0

    private func personToAdd() -> ApprovalRequest {
        if !requests.contains(.candice) {
            .candice
        } else if !requests.contains(.kai) {
            .kai
        } else if !requests.contains(.gerte) {
            .gerte
        } else {
            .sam
        }
    }

    private var addPersonButtonText: String? {
        switch requests.count {
        case ...0:
            "Add request"
        case 1:
            "Add to bottom of stack"
        case 2, 3:
            "Add more"
        default:
            nil
        }
    }

    var body: some View {
        VStack {
            VStack {
                Text("\(self.height)")

                Button(String("Reset")) {
                    withAnimation(.quickSpring()) {
                        self.viewModel.requests = Self.startingRequests
                    }
                }

                if let addPersonButtonText {
                    Button(addPersonButtonText) {
                        withAnimation(.quickSpring()) {
                            self.viewModel.requests.append(personToAdd())
                        }
                    }
                    .animation(.none, value: requests)
                }
            }
            .frame(maxWidth: .infinity)
            .onAppear {
                self.viewModel.requests = Self.startingRequests
            }

            Spacer()

            ApprovalRequestStack(
                viewModel: self.viewModel,
                didTapMore: { _ in },
                didChangeHeight: { height in self.height = height }
            )
        }
    }

    private func didTapButton(_ request: ApprovalRequest) {
        if requests.count > 2 {
            let firstItemID = requests[0].id
            var newRequests = requests
            newRequests.removeFirst()
            newRequests[0].id = firstItemID
            withAnimation(.quickSpring()) {
                self.viewModel.requests = newRequests
            }
        } else {
            withAnimation(.quickSpring()) {
                self.viewModel.requests.removeAll { $0 == request }
            }
        }
    }
}

#Preview() {
    PreviewView()
        .padding()
}

#endif

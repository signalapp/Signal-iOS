//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import SwiftUI
import LibSignalClient
import SignalServiceKit

// MARK: ApprovalRequest

struct CallLinkApprovalRequest: Hashable, Identifiable {
    /// View ID. Shouldn't be tied to the content so that the
    /// content can change without being seen as a new view.
    var id: UUID
    var aci: Aci
    var address: SignalServiceAddress
    var name: String

    init(aci: Aci, name: String) {
        self.id = aci.rawUUID
        self.aci = aci
        self.address = .init(aci)
        self.name = name
    }
}

// MARK: - CallLinkApprovalViewModel

@MainActor
class CallLinkApprovalViewModel: ObservableObject {
    typealias ApprovalRequest = CallLinkApprovalRequest

    private struct Deps {
        let contactsManager: any ContactManager
        let db: any DB
    }

    private let deps = Deps(
        contactsManager: SSKEnvironment.shared.contactManagerRef,
        db: DependenciesBridge.shared.db
    )

    @Published var requests: [ApprovalRequest] = []
    /// When bulk approving or denying requests, we want to hide all requests
    /// at once, even if it takes a moment for the requests to process,
    /// so explicitly ignore them.
    private var requestsToIgnore = Set<Aci>()

    enum RequestAction {
        case approve, deny, viewDetails
    }

    let performRequestAction = PassthroughSubject<(RequestAction, ApprovalRequest), Never>()

    func loadRequestsWithSneakyTransaction(for uuids: [UUID]) {
        let oldRequests = self.requests
        let allAcis = uuids.map(Aci.init(fromUUID:))

        // Once an ignored request is no longer in the list,
        // stop ignoring it in case they request again.
        requestsToIgnore.formIntersection(allAcis)

        let acis = allAcis.filter { !requestsToIgnore.contains($0) }

        guard oldRequests.map(\.aci) != acis else { return }

        if uuids.isEmpty {
            // Avoid opening database transaction
            withAnimation(.quickSpring()) {
                self.requests.removeAll()
            }
            return
        }

        let nameConfig: DisplayName.Config = .current()
        let names = self.deps.db.read { tx in
            self.deps.contactsManager.displayNames(
                for: acis.map(SignalServiceAddress.init),
                tx: SDSDB.shimOnlyBridge(tx)
            )
        }.map { displayName in
            displayName.resolvedValue(config: nameConfig, useShortNameIfAvailable: false)
        }

        var requests = zip(acis, names).map { (aci, name) in
            ApprovalRequest(aci: aci, name: name)
        }

        let shouldUpdateFrontCard = requests.count > 2 || (requests.count == 2 && oldRequests.count >= 2)
        if shouldUpdateFrontCard, let oldFirstID = oldRequests.first?.id {
            requests[0].id = oldFirstID
        }

        withAnimation(.quickSpring()) {
            self.requests = requests
        }
    }

    func bulkApprove(requests: [ApprovalRequest]) {
        self.removeAndIgnore(requests: requests)
        requests.forEach { self.performRequestAction.send((.approve, $0)) }
    }

    func bulkDeny(requests: [ApprovalRequest]) {
        self.removeAndIgnore(requests: requests)
        requests.forEach { self.performRequestAction.send((.deny, $0)) }
    }

    private func removeAndIgnore(requests: [ApprovalRequest]) {
        let acis = requests.map(\.aci)
        self.requestsToIgnore.formUnion(acis)

        let requestsSet = Set(requests)
        withAnimation(.quickSpring()) {
            self.requests.removeAll(where: requestsSet.contains(_:))
        }
    }
}

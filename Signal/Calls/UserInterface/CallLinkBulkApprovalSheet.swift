//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import Combine
import SignalUI
import LibSignalClient
import SignalServiceKit

class CallLinkBulkApprovalSheet: InteractiveSheetViewController {
    fileprivate enum Constants {
        static let backgroundColor = UIColor.Signal.secondaryBackground
        static let sheetHeaderBottomPadding: CGFloat = 8
        static let avatarSizeClass = ConversationAvatarView.Configuration.SizeClass.thirtySix
        static var avatarWidth: CGFloat { avatarSizeClass.size.width }
        static let avatarSpacing: CGFloat = 12
        static let buttonSpacing: CGFloat = 16
        static var buttonSize: CGFloat {
            max(UIFont.dynamicTypeTitle1Clamped.pointSize, 28)
        }
        static let denyButtonColor = UIColor.Signal.red
        static let approveButtonColor = UIColor.Signal.green
        static let selectedButtonColor = UIColor.Signal.primaryFill

        static let denyAllButtonTitle = OWSLocalizedString(
            "CALL_LINK_REQUEST_SHEET_DENY_ALL_BUTTON",
            comment: "Title for button to deny all requests to join a call."
        )
        static let approveAllButtonTitle = OWSLocalizedString(
            "CALL_LINK_REQUEST_SHEET_APPROVE_ALL_BUTTON",
            comment: "Title for button to approve all requests to join a call."
        )
    }

    override var interactiveScrollViews: [UIScrollView] { [tableView] }
    override var sheetBackgroundColor: UIColor {
        Constants.backgroundColor
    }
    override var handleBackgroundColor: UIColor {
        UIColor.Signal.transparentSeparator
    }

    typealias Request = CallLinkApprovalRequest

    private var viewModel: CallLinkApprovalViewModel
    private var subscriptions = Set<AnyCancellable>()

    // MARK: Views

    private let sheetHeader: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeHeadline
        label.textColor = .Signal.label
        label.textAlignment = .center
        label.text = OWSLocalizedString(
            "CALL_LINK_REQUEST_SHEET_HEADER",
            comment: "Header for the sheet displaying a list of requests to join a call."
        )
        return label
    }()

    private let sheetFooter: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = .init(
            top: 8,
            leading: 16,
            bottom: 16,
            trailing: 16
        )
        return stackView
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.backgroundColor = Constants.backgroundColor
        tableView.separatorInset.leading += Constants.avatarWidth + Constants.avatarSpacing
        return tableView
    }()

    private lazy var tableHeader = TableHeader()

    private class TableHeader: UIView {
        var requestCount: Int = 0 {
            didSet { self.updateText() }
        }

        private lazy var label: UILabel = {
            let label = UILabel()
            self.addSubview(label)
            self.layoutMargins.top = 36
            label.autoPinEdgesToSuperviewMargins()
            label.font = .dynamicTypeHeadline
            label.textColor = .Signal.label
            return label
        }()

        private func updateText() {
            self.label.text = String(
                format: OWSLocalizedString(
                    "CALL_LINK_REQUEST_HEADER_COUNT_%d",
                    tableName: "PluralAware",
                    comment: "Header for a table section which lists users requesting to join a call. Embeds {{ number of requests }}"
                ),
                self.requestCount
            )
        }
    }

    // MARK: init

    init(viewModel: CallLinkApprovalViewModel) {
        self.viewModel = viewModel
        super.init()
        self.overrideUserInterfaceStyle = .dark

        self.contentView.addSubview(sheetHeader)
        sheetHeader.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)

        self.contentView.addSubview(tableView)
        tableView.autoPinEdge(.top, to: .bottom, of: sheetHeader, withOffset: Constants.sheetHeaderBottomPadding)
        tableView.autoPinWidthToSuperview()

        let denyAllButton = bulkActionButton(
            title: Constants.denyAllButtonTitle,
            color: .clear
        ) { [weak self] in
            self?.didTapDenyAll()
        }

        let approveAllButton = bulkActionButton(
            title: Constants.approveAllButtonTitle,
            color: .Signal.tertiaryFill
        ) { [weak self] in
            self?.didTapApproveAll()
        }

        self.contentView.addSubview(sheetFooter)
        sheetFooter.autoPinEdge(.top, to: .bottom, of: tableView)
        sheetFooter.autoPinEdge(toSuperviewMargin: .bottom)
        sheetFooter.autoPinWidthToSuperview()
        sheetFooter.addArrangedSubview(denyAllButton)
        sheetFooter.addArrangedSubview(.hStretchingSpacer())
        sheetFooter.addArrangedSubview(approveAllButton)

        tableView.register(RequestCell.self)

        viewModel.$requests
            .removeDuplicates()
            .sink { [weak self] requests in
                self?.updateSnapshot(requests: requests)
            }
            .store(in: &subscriptions)

        tableView
            .publisher(for: \.contentSize)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateSheetSize()
            }
            .store(in: &subscriptions)
    }

    private func bulkActionButton(
        title: String,
        color: UIColor,
        action: @escaping () -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.background.cornerRadius = 12
        configuration.baseBackgroundColor = color
        configuration.baseForegroundColor = .Signal.label
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeHeadlineClamped)
        configuration.contentInsets = .init(hMargin: 16, vMargin: 14)

        return UIButton(
            configuration: configuration,
            primaryAction: .init(title: title) { _  in action() }
        )
    }

    // MARK: Presentation

    private weak var fromViewController: UIViewController?

    func present(
        from viewController: UIViewController,
        dismissalDelegate: (any SheetDismissalDelegate)? = nil
    ) {
        self.fromViewController = viewController
        self.dismissalDelegate = dismissalDelegate
        viewController.present(self, animated: true)
    }

    // MARK: Sheet sizing

    /// `minimizedHeight` doesn't animate, so don't update it after the sheet is presented.
    private var shouldUpdateMinimizedHeight = true
    private var viewHasAppeared = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.viewHasAppeared = true
    }

    private var desiredSheetHeight: CGFloat {
        InteractiveSheetViewController.Constants.handleHeight
        + contentView.layoutMargins.totalHeight
        + sheetHeader.height
        + Constants.sheetHeaderBottomPadding
        + tableView.contentSize.height
        + tableView.contentInset.totalHeight
        + sheetFooter.height
    }

    private func updateSheetSize() {
        let desiredHeight = desiredSheetHeight
        self.preferredSize = desiredHeight

        if shouldUpdateMinimizedHeight {
            self.minimizedHeight = desiredHeight
        }
        self.tableView.isScrollEnabled = self.maxHeight < desiredHeight
    }

    private lazy var preferredSize: CGFloat = self.maximumAllowedHeight()

    override func maximumPreferredHeight() -> CGFloat {
        min(preferredSize, maximumAllowedHeight())
    }

    // MARK: Actions

    private func didTapDenyAll() {
        let requestsAtTimeOfPrompt = self.viewModel.requests
        self.performWithActionSheetConfirmation(
            title: String(
                format: OWSLocalizedString(
                    "CALL_LINK_DENY_ALL_REQUESTS_CONFIRMATION_TITLE_%ld",
                    tableName: "PluralAware",
                    comment: "Title for confirmation sheet when denying all requests to join a call."
                ),
                requestsAtTimeOfPrompt.count
            ),
            message: String(
                format: OWSLocalizedString(
                    "CALL_LINK_DENY_ALL_REQUESTS_CONFIRMATION_BODY_%ld",
                    tableName: "PluralAware",
                    comment: "Body for confirmation sheet when denying all requests to join a call."
                ),
                requestsAtTimeOfPrompt.count
            ),
            confirmButtonTitle: Constants.denyAllButtonTitle
        ) { [viewModel] in
            viewModel.bulkDeny(requests: requestsAtTimeOfPrompt)
        }
    }

    private func didTapApproveAll() {
        let requestsAtTimeOfPrompt = self.viewModel.requests
        guard !requestsAtTimeOfPrompt.isEmpty else {
            return self.dismiss(animated: true)
        }

        self.performWithActionSheetConfirmation(
            title: String(
                format: OWSLocalizedString(
                    "CALL_LINK_APPROVE_ALL_REQUESTS_CONFIRMATION_TITLE_%ld",
                    tableName: "PluralAware",
                    comment: "Title for confirmation sheet when approving all requests to join a call."
                ),
                requestsAtTimeOfPrompt.count
            ),
            message: String(
                format: OWSLocalizedString(
                    "CALL_LINK_APPROVE_ALL_REQUESTS_CONFIRMATION_BODY_%ld",
                    tableName: "PluralAware",
                    comment: "Body for confirmation sheet when approving all requests to join a call."
                ),
                requestsAtTimeOfPrompt.count
            ),
            confirmButtonTitle: Constants.approveAllButtonTitle
        ) { [viewModel] in
            viewModel.bulkApprove(requests: requestsAtTimeOfPrompt)
        }
    }

    private func performWithActionSheetConfirmation(
        title: String,
        message: String,
        confirmButtonTitle: String,
        action: @escaping () -> Void
    ) {
        guard let fromViewController else {
            return owsFailDebug("Missing parent view controller")
        }

        let actionSheet = ActionSheetController(
            title: title,
            message: message,
            theme: .translucentDark
        )
        actionSheet.addAction(.init(title: confirmButtonTitle) { _ in action() })
        actionSheet.addAction(.cancel)

        self.dismiss(animated: true) {
            fromViewController.presentActionSheet(actionSheet)
        }
    }

    // MARK: Table contents

    private typealias DiffableDataSource = UITableViewDiffableDataSource<Section, Aci>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Section, Aci>

    enum Section: Hashable {
        case requests
    }

    private lazy var dataSource = DiffableDataSource(
        tableView: self.tableView
    ) { [weak self] tableView, indexPath, itemIdentifier in
        let cell = tableView.dequeueReusableCell(RequestCell.self)
        cell?.approvalViewModel = self?.viewModel
        cell?.rowModel = self?.rowModelsByID[itemIdentifier]
        return cell
    }

    fileprivate class RowModel: ObservableObject {
        let request: Request
        @Published var status: Status

        init(request: Request, status: Status) {
            self.request = request
            self.status = status
        }

        enum Status {
            case pending, approved, denied
        }
    }

    private var rowModels: [RowModel] = [] {
        didSet {
            rowModels.forEach { requestStatus in
                rowModelsByID[requestStatus.request.aci] = requestStatus
            }
        }
    }
    private var rowModelsByID: [Aci: RowModel] = [:]

    private func updateSnapshot(requests: [Request]) {
        let pendingRequests = requests.filter { request in
            (rowModelsByID[request.aci]?.status ?? .pending) == .pending
        }

        if self.tableHeader.requestCount != pendingRequests.count, self.viewHasAppeared {
            self.shouldUpdateMinimizedHeight = false
        }

        self.tableHeader.requestCount = pendingRequests.count

        // We want to keep users in this list after they're approved or denied,
        // so remove only pending users who are no longer in the peek info.
        let newRequests = Set(requests.map(\.aci))
        self.rowModels.removeAll { requestStatus in
            requestStatus.status == .pending && !newRequests.contains(requestStatus.request.aci)
        }

        let existingRequests = Set(self.rowModels.map(\.request.aci))
        self.rowModels += requests
            .filter { !existingRequests.contains($0.aci) }
            .map { RowModel(request: $0, status: .pending) }

        let requests = self.rowModels.map(\.request.aci)

        var snapshot = Snapshot()
        snapshot.appendSections([.requests])
        snapshot.appendItems(requests, toSection: .requests)
        dataSource.apply(snapshot)
    }
}

// MARK: UITableViewDelegate

extension CallLinkBulkApprovalSheet: UITableViewDelegate {
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        self.tableHeader
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard
            let aci = dataSource.itemIdentifier(for: indexPath),
            let rowModel = rowModelsByID[aci]
        else {
            return owsFailDebug("Missing request object")
        }
        viewModel.performRequestAction.send((.viewDetails, rowModel.request))
    }
}

// MARK: - RequestCell

private class RequestCell: UITableViewCell, ReusableTableViewCell {
    static var reuseIdentifier: String = "RequestCell"

    private typealias Constants = CallLinkBulkApprovalSheet.Constants
    typealias RowModel = CallLinkBulkApprovalSheet.RowModel

    var rowModel: RowModel? {
        didSet {
            loadRequestContents()
        }
    }

    var approvalViewModel: CallLinkApprovalViewModel?

    private var requestStatusSubscription: AnyCancellable?

    private var avatarView = ConversationAvatarView(
        sizeClass: Constants.avatarSizeClass,
        localUserDisplayMode: .asUser,
        badged: true
    )

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeBodyClamped
        label.textColor = .Signal.label
        return label
    }()

    private lazy var denyButton = ActionButton(icon: .xBold) { [weak self] in
        if let request = self?.rowModel?.request {
            self?.approvalViewModel?.performRequestAction.send((.deny, request))
            self?.rowModel?.status = .denied
        }
    }

    private lazy var approveButton = ActionButton(icon: .checkmarkBold) { [weak self] in
        if let request = self?.rowModel?.request {
            self?.approvalViewModel?.performRequestAction.send((.approve, request))
            self?.rowModel?.status = .approved
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let hStack = UIStackView()
        hStack.alignment = .center
        hStack.axis = .horizontal
        hStack.spacing = 8

        hStack.addArrangedSubview(avatarView)
        hStack.setCustomSpacing(Constants.avatarSpacing, after: avatarView)

        hStack.addArrangedSubview(nameLabel)

        hStack.addArrangedSubview(denyButton)
        hStack.setCustomSpacing(Constants.buttonSpacing, after: denyButton)
        hStack.addArrangedSubview(approveButton)

        contentView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func loadRequestContents() {
        guard let rowModel else { return }
        avatarView.updateWithSneakyTransactionIfNecessary { configuration in
            configuration.dataSource = .address(rowModel.request.address)
        }
        nameLabel.text = rowModel.request.name

        requestStatusSubscription = rowModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                UIView.animate(withDuration: 0.1) {
                    self.statusDidChange(to: status)
                }
            }
    }

    private func statusDidChange(to status: RowModel.Status) {
        switch status {
        case .pending:
            self.denyButton.layer.opacity = 1
            self.approveButton.layer.opacity = 1
            self.denyButton.backgroundColor = Constants.denyButtonColor
            self.approveButton.backgroundColor = Constants.approveButtonColor
        case .approved:
            self.denyButton.layer.opacity = 0
            self.approveButton.layer.opacity = 1
            self.approveButton.backgroundColor = Constants.selectedButtonColor
        case .denied:
            self.denyButton.layer.opacity = 1
            self.denyButton.backgroundColor = Constants.selectedButtonColor
            self.approveButton.layer.opacity = 0
        }
    }

    // MARK: ActionButton

    private class ActionButton: UIButton {
        private var sizeConstraints: [NSLayoutConstraint] = []

        convenience init(icon: ThemeIcon, action: @escaping () -> Void) {
            self.init(primaryAction: .init(image: Theme.iconImage(icon)) { _ in
                action()
            })
            self.titleLabel?.font = .dynamicTypeBody.bold()
            self.ows_imageEdgeInsets = .init(margin: 6)
            self.tintColor = .Signal.label
            self.sizeConstraints = self.autoSetDimensions(to: .square(Constants.buttonSize))
            self.layer.cornerRadius = Constants.buttonSize / 2
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            self.sizeConstraints.forEach { $0.constant = Constants.buttonSize }
            self.layer.cornerRadius = Constants.buttonSize / 2
        }
    }
}

// MARK: - Previews

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    SheetPreviewViewController {
        let viewModel = CallLinkApprovalViewModel()
        viewModel.requests = [
            .init(aci: .init(fromUUID: UUID()), name: "Candice"),
            .init(aci: .init(fromUUID: UUID()), name: "Sam"),
            .init(aci: .init(fromUUID: UUID()), name: "Kai"),
        ]

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            viewModel.requests.append(.init(aci: .init(fromUUID: UUID()), name: "Gerte"))
        }

        return CallLinkBulkApprovalSheet(viewModel: viewModel)
    }
}
#endif

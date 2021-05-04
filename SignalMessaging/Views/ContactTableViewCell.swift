//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
open class ContactTableViewCell: UITableViewCell {

    @objc
    open class var reuseIdentifier: String { "ContactTableViewCell" }

    private let cellView = ContactCellView()

    // TODO:
    private let allowUserInteraction: Bool

    @objc
    public override var accessoryView: UIView? {
        didSet {
            owsFailDebug("Use ows_setAccessoryView instead.")
        }
    }

    override convenience init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.init(style: style, reuseIdentifier: reuseIdentifier, allowUserInteraction: false)
    }

    @objc
    public init(style: UITableViewCell.CellStyle,
                reuseIdentifier: String?,
                allowUserInteraction: Bool) {
        self.allowUserInteraction = allowUserInteraction

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        configure()
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        self.preservesSuperviewLayoutMargins = true
        self.contentView.preservesSuperviewLayoutMargins = true

        contentView.addSubview(cellView)
        cellView.autoPinWidthToSuperviewMargins()
        cellView.autoPinHeightToSuperview(withMargin: 7)
        cellView.isUserInteractionEnabled = self.allowUserInteraction
    }

    public func configureWithSneakyTransaction(address: SignalServiceAddress,
                                               localUserDisplayMode: LocalUserDisplayMode) {
        databaseStorage.read { transaction in
            configure(address: address,
                      localUserDisplayMode: localUserDisplayMode,
                      transaction: transaction)
        }
    }

    public func configure(address: SignalServiceAddress,
                          localUserDisplayMode: LocalUserDisplayMode,
                          transaction: SDSAnyReadTransaction) {
        let content = ConversationContent.forAddress(address, transaction: transaction)
        let configuration = ContactCellConfiguration(content: content,
                                                     localUserDisplayMode: localUserDisplayMode)
        configure(configuration: configuration, transaction: transaction)
    }

    public func configure(thread: TSThread,
                          localUserDisplayMode: LocalUserDisplayMode,
                          transaction: SDSAnyReadTransaction) {
        let configuration = ContactCellConfiguration(content: .forThread(thread),
                                                     localUserDisplayMode: localUserDisplayMode)
        configure(configuration: configuration, transaction: transaction)
    }

    @objc
    public func configure(configuration: ContactCellConfiguration,
                          transaction: SDSAnyReadTransaction) {
        OWSTableItem.configureCell(self)
        cellView.configure(configuration: configuration, transaction: transaction)
    }

    public override func prepareForReuse() {
        super.prepareForReuse()

        cellView.reset()

        self.accessoryType = .none
    }
}

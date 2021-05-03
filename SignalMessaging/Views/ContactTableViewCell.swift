//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
open class ContactTableViewCell: UITableViewCell {

    open class var reuseIdentifier: String { "ContactTableViewCell" }

    private let cellView = ContactCellView()

    // TODO:
    private let allowUserInteraction: Bool

//    @objc
//    public var accessoryMessage: String? {
//        get { cellView.accessoryMessage }
//        set { cellView.accessoryMessage = newValue }
//    }

    // - (NSAttributedString *)verifiedSubtitle
    // {
    //    return self.cellView.verifiedSubtitle;
    // }
    //
    // - (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle
    // {
    //    [self.cellView setAttributedSubtitle:attributedSubtitle];
    // }
    //
    // - (void)setSubtitle:(nullable NSString *)subtitle
    // {
    //    [self.cellView setSubtitle:subtitle];
    // }

//    @objc
//    public var useLargeAvatars: Bool {
//        get { cellView.useLargeAvatars }
//        set { cellView.useLargeAvatars = newValue }
//    }

    // - (BOOL)hasAccessoryText
    // {
    //    return [self.cellView hasAccessoryText];
    // }
    //
    // - (void)ows_setAccessoryView:(UIView *)accessoryView
    // {
    //    return [self.cellView setAccessoryView:accessoryView];
    // }
    //
    // @end
    //
    // NS_ASSUME_NONNULL_END

//    @objc
//    public var ows_accessoryView: UIView? {
//        get { cellView.ows }
//        set { cellView.accessoryMessage = newValue }
//    }

    //// This method should be called _before_ the configure... methods.
    // - (void)setAccessoryMessage:(nullable NSString *)accessoryMessage;
    //
    //// This method should be called _after_ the configure... methods.
    // - (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle;
    //
    //// This method should be called _after_ the configure... methods.
    // - (void)setSubtitle:(nullable NSString *)subtitle;
    //
    // - (void)setCustomName:(nullable NSString *)customName;
    // - (void)setCustomNameAttributed:(nullable NSAttributedString *)customName;
    //
    // - (void)setUseLargeAvatars;
    //
    // - (NSAttributedString *)verifiedSubtitle;
    //
    // - (BOOL)hasAccessoryText;
    //
    // - (void)ows_setAccessoryView:(UIView *)accessoryView;
    //

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
                                               localUserAvatarMode: LocalUserAvatarMode) {
        databaseStorage.read { transaction in
            configure(address: address,
                      localUserAvatarMode: localUserAvatarMode,
                      transaction: transaction)
        }
    }

    public func configure(address: SignalServiceAddress,
                          localUserAvatarMode: LocalUserAvatarMode,
                          transaction: SDSAnyReadTransaction) {
        let content = ConversationContent.forAddress(address, transaction: transaction)
        let configuration = ContactCellConfiguration(content: content,
                                                     localUserAvatarMode: localUserAvatarMode)
        configure(configuration: configuration, transaction: transaction)
    }

    public func configure(thread: TSThread,
                          localUserAvatarMode: LocalUserAvatarMode,
                          transaction: SDSAnyReadTransaction) {
        let configuration = ContactCellConfiguration(content: .forThread(thread),
                                                     localUserAvatarMode: localUserAvatarMode)
        configure(configuration: configuration, transaction: transaction)
    }

    @objc
    public func configure(configuration: ContactCellConfiguration,
                          transaction: SDSAnyReadTransaction) {

        OWSTableItem.configureCell(self)

        cellView.configure(configuration: configuration,
                           transaction: transaction)

        // Force layout, since imageView isn't being initally rendered on App Store optimized build.
        //
        // TODO: Is this still necessary?
        self.layoutSubviews()
    }

    public override func prepareForReuse() {
        super.prepareForReuse()

        cellView.prepareForReuse()

        self.accessoryType = .none
    }
}

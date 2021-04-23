//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "ContactTableViewCell.h"
#import "ContactCellView.h"
#import "OWSTableViewController.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface ContactTableViewCell ()

@property (nonatomic) ContactCellView *cellView;

@property (nonatomic, readonly) BOOL allowUserInteraction;

@end

#pragma mark -

@implementation ContactTableViewCell

+ (instancetype)new
{
    return [[ContactTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                       reuseIdentifier:nil
                                  allowUserInteraction:false];
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier
{
    return [self initWithStyle:style reuseIdentifier:reuseIdentifier allowUserInteraction:false];
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(nullable NSString *)reuseIdentifier
         allowUserInteraction:(BOOL)allowUserInteraction
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        _allowUserInteraction = allowUserInteraction;
        [self configure];
    }
    return self;
}

+ (NSString *)reuseIdentifier
{
    return NSStringFromClass(self.class);
}

- (void)setAccessoryView:(nullable UIView *)accessoryView
{
    OWSFailDebug(@"use ows_setAccessoryView instead.");
}

- (void)configure
{
    OWSAssertDebug(!self.cellView);

    self.preservesSuperviewLayoutMargins = YES;
    self.contentView.preservesSuperviewLayoutMargins = YES;

    self.cellView = [ContactCellView new];
    [self.contentView addSubview:self.cellView];
    [self.cellView autoPinWidthToSuperviewMargins];
    [self.cellView autoPinHeightToSuperviewWithMargin:7];
    self.cellView.userInteractionEnabled = self.allowUserInteraction;
}

- (void)configureWithSneakyTransactionWithRecipientAddress:(SignalServiceAddress *)address
                                       localUserAvatarMode:(LocalUserAvatarMode)localUserAvatarMode
{
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        [self configureWithRecipientAddress:address localUserAvatarMode:localUserAvatarMode transaction:transaction];
    }];
}

- (void)configureWithRecipientAddress:(SignalServiceAddress *)address
                  localUserAvatarMode:(LocalUserAvatarMode)localUserAvatarMode
                          transaction:(SDSAnyReadTransaction *)transaction
{
    [OWSTableItem configureCell:self];

    [self.cellView configureWithRecipientAddress:address
                             localUserAvatarMode:localUserAvatarMode
                                     transaction:transaction];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureWithThread:(TSThread *)thread
        localUserAvatarMode:(LocalUserAvatarMode)localUserAvatarMode
                transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread);

    [OWSTableItem configureCell:self];

    [self.cellView configureWithThread:thread localUserAvatarMode:localUserAvatarMode transaction:transaction];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)setAccessoryMessage:(nullable NSString *)accessoryMessage
{
    OWSAssertDebug(self.cellView);

    self.cellView.accessoryMessage = accessoryMessage;
}

- (NSAttributedString *)verifiedSubtitle
{
    return self.cellView.verifiedSubtitle;
}

- (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle
{
    [self.cellView setAttributedSubtitle:attributedSubtitle];
}

- (void)setSubtitle:(nullable NSString *)subtitle
{
    [self.cellView setSubtitle:subtitle];
}

- (void)setCustomName:(nullable NSString *)customName
{
    [self.cellView setCustomName:customName.asAttributedString];
}

- (void)setCustomNameAttributed:(nullable NSAttributedString *)customName
{
    [self.cellView setCustomName:customName];
}

- (void)setUseLargeAvatars
{
    self.cellView.useLargeAvatars = YES;
}

- (BOOL)forceDarkAppearance
{
    return self.cellView.forceDarkAppearance;
}

- (void)setForceDarkAppearance:(BOOL)forceDarkAppearance
{
    self.cellView.forceDarkAppearance = forceDarkAppearance;
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    [self.cellView prepareForReuse];

    self.accessoryType = UITableViewCellAccessoryNone;
}

- (BOOL)hasAccessoryText
{
    return [self.cellView hasAccessoryText];
}

- (void)ows_setAccessoryView:(UIView *)accessoryView
{
    return [self.cellView setAccessoryView:accessoryView];
}

@end

NS_ASSUME_NONNULL_END

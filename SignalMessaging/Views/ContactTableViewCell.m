//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ContactTableViewCell.h"
#import "ContactCellView.h"
#import "OWSTableViewController.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalServiceKit/SignalAccount.h>

NS_ASSUME_NONNULL_BEGIN

@interface ContactTableViewCell ()

@property (nonatomic) ContactCellView *cellView;

@end

#pragma mark -

@implementation ContactTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
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
    [self.cellView autoPinEdgesToSuperviewMargins];
    self.cellView.userInteractionEnabled = NO;
}

- (void)configureWithRecipientAddress:(SignalServiceAddress *)address
{
    [OWSTableItem configureCell:self];

    [self.cellView configureWithRecipientAddress:address];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread);

    [OWSTableItem configureCell:self];

    [self.cellView configureWithThread:thread transaction:transaction];

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

//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ContactTableViewCell.h"
#import "Environment.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "Signal-Swift.h"
#import "UIFont+OWS.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kContactsTable_CellReuseIdentifier = @"kContactsTable_CellReuseIdentifier";

@interface ContactTableViewCell ()

@property (nonatomic) IBOutlet UILabel *nameLabel;
@property (nonatomic) IBOutlet UIImageView *avatarView;

@end

@implementation ContactTableViewCell

- (instancetype)init
{
    if (self = [super init]) {
        [self configureProgrammatically];
    }
    return self;
}

+ (nullable NSString *)reuseIdentifier
{
    return NSStringFromClass(self.class);
}

- (nullable NSString *)reuseIdentifier
{
    return NSStringFromClass(self.class);
}

+ (CGFloat)rowHeight
{
    return 59.f;
}

- (void)configureProgrammatically
{
    const CGFloat kAvatarSize = 40.f;
    _avatarView = [AvatarImageView new];
    [self.contentView addSubview:_avatarView];

    _nameLabel = [UILabel new];
    _nameLabel.contentMode = UIViewContentModeLeft;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameLabel.font = [UIFont ows_dynamicTypeBodyFont];
    [self.contentView addSubview:_nameLabel];

    [_avatarView autoVCenterInSuperview];
    [_avatarView autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:ScaleFromIPhone5To7Plus(14.f, 20.f)];
    [_avatarView autoSetDimension:ALDimensionWidth toSize:kAvatarSize];
    [_avatarView autoSetDimension:ALDimensionHeight toSize:kAvatarSize];

    [_nameLabel autoPinEdgeToSuperviewEdge:ALEdgeRight];
    [_nameLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [_nameLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [_nameLabel autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:_avatarView withOffset:12.f];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureWithSignalAccount:(SignalAccount *)signalAccount contactsManager:(OWSContactsManager *)contactsManager
{
    [self configureWithRecipientId:signalAccount.recipientId
                        avatarName:signalAccount.contact.fullName
                       displayName:[contactsManager formattedDisplayNameForSignalAccount:signalAccount
                                                                                    font:self.nameLabel.font]
                   contactsManager:contactsManager];
}

- (void)configureWithRecipientId:(NSString *)recipientId contactsManager:(OWSContactsManager *)contactsManager
{
    [self
        configureWithRecipientId:recipientId
                      avatarName:@""
                     displayName:[contactsManager formattedFullNameForRecipientId:recipientId font:self.nameLabel.font]
                 contactsManager:contactsManager];
}

- (void)configureWithRecipientId:(NSString *)recipientId
                      avatarName:(NSString *)avatarName
                     displayName:(NSAttributedString *)displayName
                 contactsManager:(OWSContactsManager *)contactsManager
{
    NSMutableAttributedString *attributedText = [displayName mutableCopy];
    if (self.accessoryMessage) {
        UILabel *blockedLabel = [[UILabel alloc] init];
        blockedLabel.textAlignment = NSTextAlignmentRight;
        blockedLabel.text = self.accessoryMessage;
        blockedLabel.font = [UIFont ows_mediumFontWithSize:13.f];
        blockedLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
        [blockedLabel sizeToFit];

        self.accessoryView = blockedLabel;
    }
    self.nameLabel.attributedText = attributedText;
    self.avatarView.image =
        [[[OWSContactAvatarBuilder alloc] initWithContactId:recipientId name:avatarName contactsManager:contactsManager]
            build];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureWithThread:(TSThread *)thread contactsManager:(OWSContactsManager *)contactsManager
{
    OWSAssert(thread);

    NSString *threadName = thread.name;
    if (threadName.length == 0 && [thread isKindOfClass:[TSGroupThread class]]) {
        threadName = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
    }

    NSAttributedString *attributedText = [[NSAttributedString alloc]
                                          initWithString:threadName
                                          attributes:@{
                                                       NSForegroundColorAttributeName : [UIColor blackColor],
                                                       }];
    self.nameLabel.attributedText = attributedText;

    self.avatarView.image = [OWSAvatarBuilder buildImageForThread:thread contactsManager:contactsManager];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)prepareForReuse
{
    self.accessoryMessage = nil;
    self.accessoryView = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
}

@end

NS_ASSUME_NONNULL_END

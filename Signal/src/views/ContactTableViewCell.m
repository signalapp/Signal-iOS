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
const NSUInteger kContactTableViewCellAvatarSize = 40;

@interface ContactTableViewCell ()

@property (nonatomic) IBOutlet UILabel *nameLabel;
@property (nonatomic) IBOutlet UIImageView *avatarView;
@property (nonatomic, nullable) UILabel *subtitle;

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
    self.preservesSuperviewLayoutMargins = YES;
    self.contentView.preservesSuperviewLayoutMargins = YES;

    _avatarView = [AvatarImageView new];
    [self.contentView addSubview:_avatarView];

    _nameLabel = [UILabel new];
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameLabel.font = [UIFont ows_dynamicTypeBodyFont];
    [self.contentView addSubview:_nameLabel];

    [_avatarView autoVCenterInSuperview];
    [_avatarView autoPinLeadingToSuperView];
    [_avatarView autoSetDimension:ALDimensionWidth toSize:kContactTableViewCellAvatarSize];
    [_avatarView autoSetDimension:ALDimensionHeight toSize:kContactTableViewCellAvatarSize];

    [_nameLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [_nameLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [_nameLabel autoPinLeadingToTrailingOfView:_avatarView margin:12.f];
    [_nameLabel autoPinTrailingToSuperView];

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
    self.avatarView.image = [[[OWSContactAvatarBuilder alloc] initWithContactId:recipientId
                                                                           name:avatarName
                                                                contactsManager:contactsManager
                                                                       diameter:kContactTableViewCellAvatarSize] build];

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

    self.avatarView.image = [OWSAvatarBuilder buildImageForThread:thread
                                                  contactsManager:contactsManager
                                                         diameter:kContactTableViewCellAvatarSize];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)addVerifiedSubtitle
{
    [self.subtitle removeFromSuperview];

    const CGFloat kSubtitlePointSize = 10.f;
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    // "checkmark"
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:@"\uf00c "
                                         attributes:@{
                                             NSFontAttributeName : [UIFont ows_fontAwesomeFont:kSubtitlePointSize],
                                         }]];
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:NSLocalizedString(@"PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
                                                        @"Badge indicating that the user is verified.")]];
    self.subtitle = [UILabel new];
    self.subtitle.font = [UIFont ows_regularFontWithSize:kSubtitlePointSize];
    self.subtitle.textColor = [UIColor ows_darkGrayColor];
    self.subtitle.attributedText = text;
    [self.subtitle sizeToFit];
    [self.contentView addSubview:self.subtitle];

    [self setNeedsLayout];
}

- (void)setFrame:(CGRect)frame
{
    [super setFrame:frame];

    [self layoutSubviews];
}

- (void)setBounds:(CGRect)bounds
{
    [super setBounds:bounds];

    [self layoutSubviews];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    if (self.subtitle) {
        OWSAssert(self.nameLabel.superview == self.contentView);
        const CGFloat kSubtitleVMargin
            = ((self.contentView.height - self.nameLabel.font.lineHeight) * 0.5f - self.subtitle.height) * 0.5f;
        self.subtitle.frame = CGRectMake(self.nameLabel.left,
            round((self.contentView.height - self.subtitle.height) - kSubtitleVMargin),
            self.subtitle.width,
            self.subtitle.height);
    }
}

- (void)prepareForReuse
{
    self.accessoryMessage = nil;
    self.accessoryView = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
    [self.subtitle removeFromSuperview];
    self.subtitle = nil;
}

@end

NS_ASSUME_NONNULL_END

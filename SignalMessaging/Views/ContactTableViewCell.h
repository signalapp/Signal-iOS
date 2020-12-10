//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SignalServiceAddress;
@class TSThread;

@interface ContactTableViewCell : UITableViewCell

@property (assign, nonatomic) BOOL forceDarkAppearance;

+ (NSString *)reuseIdentifier;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier;

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(nullable NSString *)reuseIdentifier
         allowUserInteraction:(BOOL)allowUserInteraction NS_DESIGNATED_INITIALIZER;

- (void)configureWithRecipientAddressWithSneakyTransaction:(SignalServiceAddress *)address
    NS_SWIFT_NAME(configureWithSneakyTransaction(recipientAddress:));

- (void)configureWithRecipientAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (void)configureWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;

// This method should be called _before_ the configure... methods.
- (void)setAccessoryMessage:(nullable NSString *)accessoryMessage;

// This method should be called _after_ the configure... methods.
- (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle;

- (void)setCustomName:(nullable NSString *)customName;
- (void)setCustomNameAttributed:(nullable NSAttributedString *)customName;

- (void)setCustomAvatar:(nullable UIImage *)customAvatar;

- (void)setUseSmallAvatars;

- (NSAttributedString *)verifiedSubtitle;

- (BOOL)hasAccessoryText;

- (void)ows_setAccessoryView:(UIView *)accessoryView;

@end

NS_ASSUME_NONNULL_END

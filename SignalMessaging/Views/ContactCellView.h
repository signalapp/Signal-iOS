//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kContactCellAvatarTextMargin;

@class SDSAnyReadTransaction;
@class SignalServiceAddress;
@class TSThread;

@interface ContactCellView : UIStackView

@property (assign, nonatomic) BOOL forceDarkAppearance;

@property (nonatomic, nullable) NSString *accessoryMessage;

@property (nonatomic, nullable) NSAttributedString *customName;

@property (nonatomic, nullable) UIImage *customAvatar;

@property (nonatomic) BOOL useSmallAvatars;

- (void)configureWithRecipientAddressWithSneakyTransaction:(SignalServiceAddress *)address
    NS_SWIFT_NAME(configureWithSneakyTransaction(recipientAddress:));

- (void)configureWithRecipientAddress:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (void)configureWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;

- (void)prepareForReuse;

- (NSAttributedString *)verifiedSubtitle;

- (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle;

- (BOOL)hasAccessoryText;

- (void)setAccessoryView:(UIView *)accessoryView;

@end

NS_ASSUME_NONNULL_END

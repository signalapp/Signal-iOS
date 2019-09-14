//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kContactCellAvatarTextMargin;

@class SDSAnyReadTransaction;
@class SignalServiceAddress;
@class TSThread;

@interface ContactCellView : UIStackView

@property (nonatomic, nullable) NSString *accessoryMessage;

- (void)configureWithRecipientAddress:(SignalServiceAddress *)address;

- (void)configureWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;

- (void)prepareForReuse;

- (NSAttributedString *)verifiedSubtitle;

- (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle;

- (BOOL)hasAccessoryText;

- (void)setAccessoryView:(UIView *)accessoryView;

@end

NS_ASSUME_NONNULL_END

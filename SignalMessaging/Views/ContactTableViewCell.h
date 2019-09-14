//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SignalServiceAddress;
@class TSThread;

@interface ContactTableViewCell : UITableViewCell

+ (NSString *)reuseIdentifier;

- (void)configureWithRecipientAddress:(SignalServiceAddress *)address;

- (void)configureWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;

// This method should be called _before_ the configure... methods.
- (void)setAccessoryMessage:(nullable NSString *)accessoryMessage;

// This method should be called _after_ the configure... methods.
- (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle;

- (NSAttributedString *)verifiedSubtitle;

- (BOOL)hasAccessoryText;

- (void)ows_setAccessoryView:(UIView *)accessoryView;

@end

NS_ASSUME_NONNULL_END

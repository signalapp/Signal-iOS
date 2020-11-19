//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kContactCellAvatarTextMargin;

@class TSThread;

@interface ContactCellView : UIStackView

@property (nonatomic, nullable) NSString *accessoryMessage;

- (void)configureWithRecipientId:(NSString *)recipientId;

- (void)configureWithThread:(TSThread *)thread;

- (void)prepareForReuse;

- (NSAttributedString *)verifiedSubtitle;

- (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle;

- (BOOL)hasAccessoryText;

- (void)setAccessoryView:(UIView *)accessoryView;

@end

NS_ASSUME_NONNULL_END

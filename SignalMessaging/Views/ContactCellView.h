//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kContactCellAvatarSize;
extern const CGFloat kContactCellAvatarTextMargin;

@class OWSContactsManager;
@class SignalAccount;
@class TSThread;

@interface ContactCellView : UIView

@property (nonatomic, nullable) NSString *accessoryMessage;

- (void)configureWithSignalAccount:(SignalAccount *)signalAccount contactsManager:(OWSContactsManager *)contactsManager;

- (void)configureWithRecipientId:(NSString *)recipientId contactsManager:(OWSContactsManager *)contactsManager;

- (void)configureWithThread:(TSThread *)thread contactsManager:(OWSContactsManager *)contactsManager;

- (void)prepareForReuse;

- (NSAttributedString *)verifiedSubtitle;

- (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle;

- (BOOL)hasAccessoryText;

- (void)setAccessoryView:(UIView *)accessoryView;

@end

NS_ASSUME_NONNULL_END

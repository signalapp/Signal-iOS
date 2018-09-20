//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsManager.h"

NS_ASSUME_NONNULL_BEGIN

@class FLContactsManager;
@class TSThread;

@interface ContactTableViewCell : UITableViewCell

+ (NSString *)reuseIdentifier;

- (void)configureWithRecipientId:(NSString *)recipientId contactsManager:(FLContactsManager *)contactsManager;

- (void)configureWithThread:(TSThread *)thread contactsManager:(FLContactsManager *)contactsManager;

// This method should be called _before_ the configure... methods.
- (void)setAccessoryMessage:(nullable NSString *)accessoryMessage;

// This method should be called _after_ the configure... methods.
- (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle;

- (NSAttributedString *)verifiedSubtitle;

- (BOOL)hasAccessoryText;

- (void)ows_setAccessoryView:(UIView *)accessoryView;

@end

NS_ASSUME_NONNULL_END

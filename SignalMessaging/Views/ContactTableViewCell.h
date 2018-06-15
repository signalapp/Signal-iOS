//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsManager.h"

/**
 *
 * ContactTableViewCell displays a contact from a Contact object.
 *
 */

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kContactTableViewCellAvatarSize;
extern const CGFloat kContactTableViewCellAvatarTextMargin;

@class OWSContactsManager;
@class SignalAccount;
@class TSThread;

@interface ContactTableViewCell : UITableViewCell

@property (nonatomic, nullable) NSString *accessoryMessage;
@property (nonatomic, readonly) UILabel *subtitle;

+ (NSString *)reuseIdentifier;

- (void)configureWithSignalAccount:(SignalAccount *)signalAccount contactsManager:(OWSContactsManager *)contactsManager;

- (void)configureWithRecipientId:(NSString *)recipientId contactsManager:(OWSContactsManager *)contactsManager;

- (void)configureWithThread:(TSThread *)thread contactsManager:(OWSContactsManager *)contactsManager;

- (NSAttributedString *)verifiedSubtitle;

@end

NS_ASSUME_NONNULL_END

//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsManager.h"

/**
 *
 * ContactTableViewCell displays a contact from a Contact object.
 *
 */

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kContactsTable_CellReuseIdentifier;
extern const NSUInteger kContactTableViewCellAvatarSize;
extern const CGFloat kContactTableViewCellAvatarTextMargin;

@class OWSContactsManager;
@class SignalAccount;
@class TSThread;

@interface ContactTableViewCell : UITableViewCell

@property (nonatomic, nullable) NSString *accessoryMessage;
@property (nonatomic, readonly) UILabel *subtitle;

+ (nullable NSString *)reuseIdentifier;

+ (CGFloat)rowHeight;

- (void)configureWithSignalAccount:(SignalAccount *)signalAccount contactsManager:(OWSContactsManager *)contactsManager;

- (void)configureWithRecipientId:(NSString *)recipientId contactsManager:(OWSContactsManager *)contactsManager;

- (void)configureWithThread:(TSThread *)thread contactsManager:(OWSContactsManager *)contactsManager;

- (NSAttributedString *)verifiedSubtitle;

@end

NS_ASSUME_NONNULL_END

//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSThread;
@class OWSContactsManager;

@interface InboxTableViewCell : UITableViewCell

+ (NSString *)cellReuseIdentifier;

- (void)configureWithThread:(TSThread *)thread
            contactsManager:(OWSContactsManager *)contactsManager
      blockedPhoneNumberSet:(NSSet<NSString *> *)blockedPhoneNumberSet;

@end

NS_ASSUME_NONNULL_END

//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSContactsManager;
@class TSThread;

@interface HomeViewCell : UITableViewCell

+ (CGFloat)rowHeight;

+ (NSString *)cellReuseIdentifier;

- (void)configureWithThread:(TSThread *)thread
            contactsManager:(OWSContactsManager *)contactsManager
      blockedPhoneNumberSet:(NSSet<NSString *> *)blockedPhoneNumberSet;

@end

NS_ASSUME_NONNULL_END

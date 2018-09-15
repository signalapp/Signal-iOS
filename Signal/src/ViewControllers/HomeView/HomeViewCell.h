//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSContactsManager;
@class ThreadViewModel;
@class YapDatabaseReadTransaction;

@interface HomeViewCell : UITableViewCell

+ (NSString *)cellReuseIdentifier;

- (void)configureWithThread:(ThreadViewModel *)thread
            contactsManager:(OWSContactsManager *)contactsManager
                  isBlocked:(BOOL)isBlocked;

- (void)configureWithThread:(ThreadViewModel *)thread
            contactsManager:(OWSContactsManager *)contactsManager
                  isBlocked:(BOOL)isBlocked
            overrideSnippet:(nullable NSAttributedString *)overrideSnippet
               overrideDate:(nullable NSDate *)overrideDate;

@end

NS_ASSUME_NONNULL_END

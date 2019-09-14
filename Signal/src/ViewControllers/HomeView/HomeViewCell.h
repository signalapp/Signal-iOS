//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ThreadViewModel;

@interface HomeViewCell : UITableViewCell

+ (NSString *)cellReuseIdentifier;

- (void)configureWithThread:(ThreadViewModel *)thread
                  isBlocked:(BOOL)isBlocked;

- (void)configureWithThread:(ThreadViewModel *)thread
                  isBlocked:(BOOL)isBlocked
            overrideSnippet:(nullable NSAttributedString *)overrideSnippet
               overrideDate:(nullable NSDate *)overrideDate;

@end

NS_ASSUME_NONNULL_END

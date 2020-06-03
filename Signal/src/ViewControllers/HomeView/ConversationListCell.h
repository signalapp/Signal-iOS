//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ThreadViewModel;

@interface ConversationListCell : UITableViewCell

+ (NSString *)cellReuseIdentifier;

- (void)configureWithThread:(ThreadViewModel *)thread isBlocked:(BOOL)isBlocked;

- (void)configureWithThread:(ThreadViewModel *)thread
                  isBlocked:(BOOL)isBlocked
            overrideSnippet:(nullable NSAttributedString *)overrideSnippet
               overrideDate:(nullable NSDate *)overrideDate;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(nullable NSString *)reuseIdentifier NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END

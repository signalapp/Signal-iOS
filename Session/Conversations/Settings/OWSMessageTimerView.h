//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageTimerView : UIView

@property (nonatomic) UIImageView *imageView;

- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;

- (void)configureWithExpirationTimestamp:(uint64_t)expirationTimestamp
                  initialDurationSeconds:(uint32_t)initialDurationSeconds;

- (void)prepareForReuse;

+ (CGSize)measureSize;

@end

NS_ASSUME_NONNULL_END

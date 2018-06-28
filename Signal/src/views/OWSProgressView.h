//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSProgressView : UIView

@property (nonatomic) UIColor *color;
@property (nonatomic) CGFloat progress;

+ (CGSize)defaultSize;

@end

NS_ASSUME_NONNULL_END

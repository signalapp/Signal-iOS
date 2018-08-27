//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSGroupAvatarBuilder.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSGroupAvatarBuilder ()

@property (nonatomic, readonly) TSThread *thread;

@end

@implementation OWSGroupAvatarBuilder

- (instancetype)initWithThread:(TSThread *)thread
{
    self = [super init];
    if (!self) {
        return self;
    }

    _thread = thread;

    return self;
}

- (nullable UIImage *)buildSavedImage
{
    return self.thread.image;
}

- (UIImage *)buildDefaultImage
{
    static UIImage *defaultGroupImage;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultGroupImage = [UIImage imageNamed:@"empty-group-avatar"];
    });
    return defaultGroupImage;
}

@end

NS_ASSUME_NONNULL_END

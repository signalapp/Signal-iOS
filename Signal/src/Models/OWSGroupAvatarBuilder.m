//  Created by Michael Kirk on 9/26/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSGroupAvatarBuilder.h"
#import "TSGroupThread.h"
NS_ASSUME_NONNULL_BEGIN

@interface OWSGroupAvatarBuilder ()

@property (nonatomic, readonly) TSGroupThread *thread;

@end

@implementation OWSGroupAvatarBuilder

- (instancetype)initWithThread:(TSGroupThread *)thread
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
    return self.thread.groupModel.groupImage;
}

- (UIImage *)buildDefaultImage
{
    return [UIImage imageNamed:@"empty-group-avatar"];
}

@end

NS_ASSUME_NONNULL_END

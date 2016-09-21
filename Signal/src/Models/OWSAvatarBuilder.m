//  Created by Michael Kirk on 9/26/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSAvatarBuilder.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSGroupAvatarBuilder.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSAvatarBuilder

+ (UIImage *)buildImageForThread:(TSThread *)thread contactsManager:(OWSContactsManager *)contactsManager
{
    OWSAvatarBuilder *avatarBuilder;
    if ([thread isKindOfClass:[TSContactThread class]]) {
        avatarBuilder =
            [[OWSContactAvatarBuilder alloc] initWithThread:(TSContactThread *)thread contactsManager:contactsManager];
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        avatarBuilder = [[OWSGroupAvatarBuilder alloc] initWithThread:(TSGroupThread *)thread];
    } else {
        DDLogError(@"%@ called with unsupported thread: %@", self.tag, thread);
    }
    return [avatarBuilder build];
}

- (UIImage *)build
{
    UIImage *_Nullable savedImage = [self buildSavedImage];
    if (savedImage) {
        return savedImage;
    } else {
        return [self buildDefaultImage];
    }
}

- (nullable UIImage *)buildSavedImage
{
    @throw [NSException
        exceptionWithName:NSInternalInconsistencyException
                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                 userInfo:nil];
}

- (UIImage *)buildDefaultImage
{
    @throw [NSException
        exceptionWithName:NSInternalInconsistencyException
                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                 userInfo:nil];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END

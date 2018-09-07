//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugUIMessagesAction.h"
#import <SignalServiceKit/OWSPrimaryStorage.h>

NS_ASSUME_NONNULL_BEGIN

@class DebugUIMessagesSingleAction;

@interface DebugUIMessagesAction ()

@end

#pragma mark -

@interface DebugUIMessagesSingleAction ()

@property (nonatomic, nullable) ActionPrepareBlock prepareBlock;

// "Single" actions should have exactly one "staggered" or "unstaggered" action block.
@property (nonatomic, nullable) StaggeredActionBlock staggeredActionBlock;
@property (nonatomic, nullable) UnstaggeredActionBlock unstaggeredActionBlock;

@end

#pragma mark -

@implementation DebugUIMessagesAction

- (DebugUIMessagesSingleAction *)nextActionToPerform
{
    return (DebugUIMessagesSingleAction *)self;
}

- (void)prepare:(ActionSuccessBlock)success failure:(ActionFailureBlock)failure
{
    OWSAssertDebug(success);
    OWSAssertDebug(failure);

    OWSAbstractMethod();

    success();
}

- (void)prepareAndPerformNTimes:(NSUInteger)count
{
    OWSLogInfo(@"%@ prepareAndPerformNTimes: %zd", self.label, count);
    [DDLog flushLog];

    [self prepare:^{
        [self performNTimes:count
                    success:^{
                    }
                    failure:^{
                    }];
    }
          failure:^{
          }];
}

- (void)performNTimes:(NSUInteger)countParam success:(ActionSuccessBlock)success failure:(ActionFailureBlock)failure
{
    OWSAssertDebug(success);
    OWSAssertDebug(failure);

    OWSLogInfo(@"%@ performNTimes: %zd", self.label, countParam);
    [DDLog flushLog];

    if (countParam < 1) {
        success();
        return;
    }

    __block NSUInteger count = countParam;
    [OWSPrimaryStorage.sharedManager.newDatabaseConnection readWriteWithBlock:^(
        YapDatabaseReadWriteTransaction *transaction) {
        NSUInteger batchSize = 0;
        while (count > 0) {
            NSUInteger index = count;

            DebugUIMessagesSingleAction *action = [self nextActionToPerform];
            OWSAssertDebug([action isKindOfClass:[DebugUIMessagesSingleAction class]]);

            if (action.staggeredActionBlock) {
                OWSAssertDebug(!action.unstaggeredActionBlock);
                action.staggeredActionBlock(index,
                    transaction,
                    ^{
                        dispatch_after(
                            dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                OWSLogInfo(@"%@ performNTimes success: %zd", self.label, count);
                                [self performNTimes:count - 1 success:success failure:failure];
                            });
                    },
                    failure);

                break;
            } else {
                OWSAssertDebug(action.unstaggeredActionBlock);

                // TODO: We could check result for failure.
                action.unstaggeredActionBlock(index, transaction);

                const NSUInteger kMaxBatchSize = 2500;
                batchSize++;
                if (batchSize >= kMaxBatchSize) {
                    dispatch_after(
                        dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                            OWSLogInfo(@"%@ performNTimes success: %zd", self.label, count);
                            [self performNTimes:count - 1 success:success failure:failure];
                        });

                    break;
                }
                count--;
            }
        }
    }];
}

@end

#pragma mark -

@implementation DebugUIMessagesSingleAction

+ (DebugUIMessagesAction *)actionWithLabel:(NSString *)label
                      staggeredActionBlock:(StaggeredActionBlock)staggeredActionBlock
{
    OWSAssertDebug(label.length > 0);
    OWSAssertDebug(staggeredActionBlock);

    DebugUIMessagesSingleAction *instance = [DebugUIMessagesSingleAction new];
    instance.label = label;
    instance.staggeredActionBlock = staggeredActionBlock;
    return instance;
}

+ (DebugUIMessagesAction *)actionWithLabel:(NSString *)label
                    unstaggeredActionBlock:(UnstaggeredActionBlock)unstaggeredActionBlock
{
    OWSAssertDebug(label.length > 0);
    OWSAssertDebug(unstaggeredActionBlock);

    DebugUIMessagesSingleAction *instance = [DebugUIMessagesSingleAction new];
    instance.label = label;
    instance.unstaggeredActionBlock = unstaggeredActionBlock;
    return instance;
}

+ (DebugUIMessagesAction *)actionWithLabel:(NSString *)label
                      staggeredActionBlock:(StaggeredActionBlock)staggeredActionBlock
                              prepareBlock:(ActionPrepareBlock)prepareBlock
{
    OWSAssertDebug(label.length > 0);
    OWSAssertDebug(staggeredActionBlock);
    OWSAssertDebug(prepareBlock);

    DebugUIMessagesSingleAction *instance = [DebugUIMessagesSingleAction new];
    instance.label = label;
    instance.staggeredActionBlock = staggeredActionBlock;
    instance.prepareBlock = prepareBlock;
    return instance;
}

+ (DebugUIMessagesAction *)actionWithLabel:(NSString *)label
                    unstaggeredActionBlock:(UnstaggeredActionBlock)unstaggeredActionBlock
                              prepareBlock:(ActionPrepareBlock)prepareBlock
{
    OWSAssertDebug(label.length > 0);
    OWSAssertDebug(unstaggeredActionBlock);
    OWSAssertDebug(prepareBlock);

    DebugUIMessagesSingleAction *instance = [DebugUIMessagesSingleAction new];
    instance.label = label;
    instance.unstaggeredActionBlock = unstaggeredActionBlock;
    instance.prepareBlock = prepareBlock;
    return instance;
}

- (void)prepare:(ActionSuccessBlock)success failure:(ActionFailureBlock)failure
{
    OWSAssertDebug(success);
    OWSAssertDebug(failure);

    if (self.prepareBlock) {
        self.prepareBlock(success, failure);
    } else {
        success();
    }
}

@end

#pragma mark -

@interface DebugUIMessagesGroupAction ()

@property (nonatomic) SubactionMode subactionMode;
@property (nonatomic, nullable) NSArray<DebugUIMessagesAction *> *subactions;
@property (nonatomic) NSUInteger subactionIndex;

@end

#pragma mark -

@implementation DebugUIMessagesGroupAction

- (DebugUIMessagesSingleAction *)nextActionToPerform
{
    OWSAssertDebug(self.subactions.count > 0);

    switch (self.subactionMode) {
        case SubactionMode_Random: {
            DebugUIMessagesAction *subaction = self.subactions[arc4random_uniform((uint32_t)self.subactions.count)];
            OWSAssertDebug(subaction);
            return subaction.nextActionToPerform;
        }
        case SubactionMode_Ordered: {
            DebugUIMessagesAction *subaction = self.subactions[self.subactionIndex];
            OWSAssertDebug(subaction);
            self.subactionIndex = (self.subactionIndex + 1) % self.subactions.count;
            return subaction.nextActionToPerform;
        }
    }
}

- (void)prepare:(ActionSuccessBlock)success failure:(ActionFailureBlock)failure
{
    OWSAssertDebug(success);
    OWSAssertDebug(failure);

    [DebugUIMessagesGroupAction prepareSubactions:[self.subactions mutableCopy] success:success failure:failure];
}

+ (void)prepareSubactions:(NSMutableArray<DebugUIMessagesAction *> *)unpreparedSubactions
                  success:(ActionSuccessBlock)success
                  failure:(ActionFailureBlock)failure
{
    OWSAssertDebug(success);
    OWSAssertDebug(failure);

    if (unpreparedSubactions.count < 1) {
        return success();
    }

    DebugUIMessagesAction *nextAction = unpreparedSubactions.lastObject;
    [unpreparedSubactions removeLastObject];
    OWSLogInfo(@"preparing: %@", nextAction.label);
    [DDLog flushLog];
    [nextAction prepare:^{
        [self prepareSubactions:unpreparedSubactions success:success failure:failure];
    }
                failure:^{
                }];
}

+ (DebugUIMessagesAction *)randomGroupActionWithLabel:(NSString *)label
                                           subactions:(NSArray<DebugUIMessagesAction *> *)subactions
{
    OWSAssertDebug(label.length > 0);
    OWSAssertDebug(subactions.count > 0);

    DebugUIMessagesGroupAction *instance = [DebugUIMessagesGroupAction new];
    instance.label = label;
    instance.subactions = subactions;
    instance.subactionMode = SubactionMode_Random;
    return instance;
}

+ (DebugUIMessagesAction *)allGroupActionWithLabel:(NSString *)label
                                        subactions:(NSArray<DebugUIMessagesAction *> *)subactions
{
    OWSAssertDebug(label.length > 0);
    OWSAssertDebug(subactions.count > 0);

    DebugUIMessagesGroupAction *instance = [DebugUIMessagesGroupAction new];
    instance.label = label;
    instance.subactions = subactions;
    instance.subactionMode = SubactionMode_Ordered;
    return instance;
}

@end

NS_ASSUME_NONNULL_END

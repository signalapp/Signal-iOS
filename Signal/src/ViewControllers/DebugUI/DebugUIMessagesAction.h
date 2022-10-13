//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebugUIMessagesUtils.h"

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@interface DebugUIMessagesAction : NSObject

@property (nonatomic) NSString *label;

- (void)prepareAndPerformNTimes:(NSUInteger)count;

@end

#pragma mark -

@interface DebugUIMessagesSingleAction : DebugUIMessagesAction

+ (DebugUIMessagesAction *)actionWithLabel:(NSString *)label
                      staggeredActionBlock:(StaggeredActionBlock)staggeredActionBlock;

+ (DebugUIMessagesAction *)actionWithLabel:(NSString *)label
                    unstaggeredActionBlock:(UnstaggeredActionBlock)unstaggeredActionBlock;

+ (DebugUIMessagesAction *)actionWithLabel:(NSString *)label
                      staggeredActionBlock:(StaggeredActionBlock)staggeredActionBlock
                              prepareBlock:(ActionPrepareBlock)prepareBlock;

+ (DebugUIMessagesAction *)actionWithLabel:(NSString *)label
                    unstaggeredActionBlock:(UnstaggeredActionBlock)unstaggeredActionBlock
                              prepareBlock:(ActionPrepareBlock)prepareBlock;

@end

#pragma mark -

typedef NS_ENUM(NSUInteger, SubactionMode) {
    SubactionMode_Random = 0,
    SubactionMode_Ordered,
};

@interface DebugUIMessagesGroupAction : DebugUIMessagesAction

@property (nonatomic, readonly) SubactionMode subactionMode;
@property (nonatomic, readonly, nullable) NSArray<DebugUIMessagesAction *> *subactions;

// Given a group of subactions, perform a single random subaction each time.
+ (DebugUIMessagesAction *)randomGroupActionWithLabel:(NSString *)label
                                           subactions:(NSArray<DebugUIMessagesAction *> *)subactions;

// Given a group of subactions, perform the subactions in order.
//
// If prepareAndPerformNTimes: is called with count == subactions.count, all of the subactions
// are performed exactly once.
+ (DebugUIMessagesAction *)allGroupActionWithLabel:(NSString *)label
                                        subactions:(NSArray<DebugUIMessagesAction *> *)subactions;

@end

NS_ASSUME_NONNULL_END

#endif

//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface TSInteraction : TSYapDatabaseObject

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread;

@property (nonatomic, readonly) NSString *uniqueThreadId;
@property (nonatomic, readonly) TSThread *thread;
@property (nonatomic, readonly) uint64_t timestamp;

- (NSDate *)date;
- (NSString *)description;

/**
 * When an interaction is updated, it often affects the UI for it's containing thread. Touching it's thread will notify
 * any observers so they can redraw any related UI.
 */
- (void)touchThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark Utility Method

+ (NSString *)stringFromTimeStamp:(uint64_t)timestamp;
+ (uint64_t)timeStampFromString:(NSString *)string;

+ (instancetype)interactionForTimestamp:(uint64_t)timestamp
                        withTransaction:(YapDatabaseReadWriteTransaction *)transaction;

- (nullable NSDate *)receiptDateForSorting;

@end

NS_ASSUME_NONNULL_END

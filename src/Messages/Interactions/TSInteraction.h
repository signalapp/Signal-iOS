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

// NSDate has second precision, uint64_t timestamps have millisecond precision
// so prefer timestampForSorting over dateForSorting.
- (NSDate *)dateForSorting;
- (uint64_t)timestampForSorting;

// "Dynamic" interactions are not messages or static events (like
// info messages, error messages, etc.).  They are interactions
// created, updated and deleted by the views.
//
// These include block offers, "add to contact" offers,
// unseen message indicators, etc.
- (BOOL)isDynamicInteraction;

@end

NS_ASSUME_NONNULL_END

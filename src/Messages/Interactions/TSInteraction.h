//
//  TSInteraction.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabaseRelationshipNode.h>

#import "TSYapDatabaseObject.h"

#import "TSContactThread.h"
#import "TSGroupThread.h"

extern const struct TSMessageRelationships { __unsafe_unretained NSString *threadUniqueId; } TSMessageRelationships;

extern const struct TSMessageEdges { __unsafe_unretained NSString *thread; } TSMessageEdges;

@interface TSInteraction : TSYapDatabaseObject <YapDatabaseRelationshipNode>

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread;

@property (nonatomic, readonly) NSString *uniqueThreadId;
@property (nonatomic, readonly) uint64_t timestamp;

- (NSDate *)date;
- (NSString *)description;

#pragma mark Utility Method

+ (NSString *)stringFromTimeStamp:(uint64_t)timestamp;
+ (uint64_t)timeStampFromString:(NSString *)string;

+ (instancetype)interactionForTimestamp:(uint64_t)timestamp
                        withTransaction:(YapDatabaseReadWriteTransaction *)transaction;


@end

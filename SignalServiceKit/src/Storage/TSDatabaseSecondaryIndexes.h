//
//  TSDatabaseSecondaryIndexes.h
//  Signal
//
//  Created by Frederic Jacobs on 26/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <YapDatabase/YapDatabaseSecondaryIndex.h>
#import <YapDatabase/YapDatabaseTransaction.h>

@interface TSDatabaseSecondaryIndexes : NSObject

+ (YapDatabaseSecondaryIndex *)registerTimeStampIndex;

+ (void)enumerateMessagesWithTimestamp:(uint64_t)timestamp
                             withBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block
                      usingTransaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

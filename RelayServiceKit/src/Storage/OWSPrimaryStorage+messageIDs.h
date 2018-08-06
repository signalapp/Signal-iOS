//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage.h"

@interface OWSPrimaryStorage (messageIDs)

+ (NSString *)getAndIncrementMessageIdWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

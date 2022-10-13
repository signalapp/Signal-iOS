//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "NSArray+OWS.h"
#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSArray (OWS)

- (NSArray<NSString *> *)uniqueIds
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    for (id object in self) {
        OWSAssertDebug([object isKindOfClass:[TSYapDatabaseObject class]]);
        TSYapDatabaseObject *dbObject = object;
        [result addObject:dbObject.uniqueId];
    }
    return result;
}

@end

NS_ASSUME_NONNULL_END

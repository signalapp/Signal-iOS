//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "FunctionalUtil.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSArray (FunctionalUtil)

- (NSArray *)map:(id (^)(id item))projection
{
    OWSPrecondition(projection != nil);

    NSMutableArray *r = [NSMutableArray arrayWithCapacity:self.count];
    for (id e in self) {
        [r addObject:projection(e)];
    }
    return r;
}

- (NSArray *)filter:(BOOL (^)(id item))predicate
{
    OWSPrecondition(predicate != nil);

    NSMutableArray *r = [NSMutableArray array];
    for (id e in self) {
        if (predicate(e)) {
            [r addObject:e];
        }
    }
    return r;
}

@end

NS_ASSUME_NONNULL_END

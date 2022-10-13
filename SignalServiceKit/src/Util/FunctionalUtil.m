//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "FunctionalUtil.h"

NS_ASSUME_NONNULL_BEGIN

@interface FUBadArgument : NSException

+ (FUBadArgument *) new:(NSString *)reason;
+ (void)raise:(NSString *)message;

@end

@implementation FUBadArgument

+ (FUBadArgument *) new:(NSString *)reason {
    return [[FUBadArgument alloc] initWithName:@"Invalid Argument" reason:reason userInfo:nil];
}
+ (void)raise:(NSString *)message {
    [FUBadArgument raise:@"Invalid Argument" format:@"%@", message];
}

@end

#define tskit_require(expr)                                                                                            \
    if (!(expr)) {                                                                                                     \
        NSString *reason =                                                                                             \
            [NSString stringWithFormat:@"require %@ (in %s at line %d)", (@ #expr), __FILE__, __LINE__];               \
        OWSLogError(@"%@", reason);                                                                                    \
        [FUBadArgument raise:reason];                                                                                  \
    };


@implementation NSArray (FunctionalUtil)

- (nullable id)firstSatisfying:(BOOL (^)(id))predicate
{
    tskit_require(predicate != nil);
    for (id e in self) {
        if (predicate(e)) {
            return e;
        }
    }
    return nil;
}

- (BOOL)anySatisfy:(BOOL (^)(id item))predicate
{
    return [self firstSatisfying:predicate] != nil;
}

- (BOOL)allSatisfy:(BOOL (^)(id item))predicate
{
    tskit_require(predicate != nil);
    for (id e in self) {
        if (!predicate(e)) {
            return false;
        }
    }
    return true;
}

- (NSArray *)map:(id (^)(id item))projection {
    tskit_require(projection != nil);

    NSMutableArray *r = [NSMutableArray arrayWithCapacity:self.count];
    for (id e in self) {
        [r addObject:projection(e)];
    }
    return r;
}

- (NSArray *)filter:(BOOL (^)(id item))predicate
{
    tskit_require(predicate != nil);

    NSMutableArray *r = [NSMutableArray array];
    for (id e in self) {
        if (predicate(e)) {
            [r addObject:e];
        }
    }
    return r;
}

- (NSDictionary *)groupBy:(id (^)(id value))keySelector {
    tskit_require(keySelector != nil);

    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    for (id item in self) {
        id key = keySelector(item);

        NSMutableArray *group = result[key];
        if (group == nil) {
            group       = [NSMutableArray array];
            result[key] = group;
        }
        [group addObject:item];
    }

    return result;
}

@end

NS_ASSUME_NONNULL_END

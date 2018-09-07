//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "FunctionalUtil.h"

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
- (bool)any:(int (^)(id item))predicate {
    tskit_require(predicate != nil);
    for (id e in self) {
        if (predicate(e)) {
            return true;
        }
    }
    return false;
}
- (bool)all:(int (^)(id item))predicate {
    tskit_require(predicate != nil);
    for (id e in self) {
        if (!predicate(e)) {
            return false;
        }
    }
    return true;
}
- (id)firstMatchingElseNil:(int (^)(id item))predicate {
    tskit_require(predicate != nil);
    for (id e in self) {
        if (predicate(e)) {
            return e;
        }
    }
    return nil;
}
- (NSArray *)map:(id (^)(id item))projection {
    tskit_require(projection != nil);

    NSMutableArray *r = [NSMutableArray arrayWithCapacity:self.count];
    for (id e in self) {
        [r addObject:projection(e)];
    }
    return r;
}
- (NSArray *)filter:(int (^)(id item))predicate {
    tskit_require(predicate != nil);

    NSMutableArray *r = [NSMutableArray array];
    for (id e in self) {
        if (predicate(e)) {
            [r addObject:e];
        }
    }
    return r;
}

- (NSDictionary *)keyedBy:(id (^)(id value))keySelector {
    tskit_require(keySelector != nil);

    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    for (id value in self) {
        result[keySelector(value)] = value;
    }
    tskit_require(result.count == self.count);

    return result;
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

//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AnonymousConditionLogger.h"
#import "AnonymousOccurrenceLogger.h"
#import "AnonymousValueLogger.h"
#import "CategorizingLogger.h"
#import "LoggingUtil.h"

@implementation CategorizingLogger

+ (CategorizingLogger *)categorizingLogger {
    CategorizingLogger *c = [CategorizingLogger new];
    c->callbacks          = [NSMutableArray array];
    c->indexDic           = [NSMutableDictionary dictionary];
    return c;
}
- (void)addLoggingCallback:(void (^)(NSString *category, id details, NSUInteger index))callback {
    [callbacks addObject:[callback copy]];
}

- (void)log:(NSString *)category details:(id)details {
    NSNumber *index = indexDic[category];
    if (index == nil) {
        index              = @(indexDic.count);
        indexDic[category] = index;
    }
    NSUInteger x = [index unsignedIntegerValue];
    for (void (^callback)(NSString *category, id details, NSUInteger index) in callbacks) {
        callback(category, details, x);
    }
}

- (id<ValueLogger>)getValueLoggerForValue:(id)valueIdentity from:(id)sender {
    id<ValueLogger> r = [AnonymousValueLogger anonymousValueLogger:^(double value) {
      [self log:[NSString stringWithFormat:@"Value %@ from %@", valueIdentity, sender] details:@(value)];
    }];
    return [LoggingUtil throttleValueLogger:r discardingAfterEventForDuration:0.5];
}
- (id<OccurrenceLogger>)getOccurrenceLoggerForSender:(id)sender withKey:(NSString *)key {
    id<OccurrenceLogger> r = [AnonymousOccurrenceLogger anonymousOccurencyLoggerWithMarker:^(id details) {
      [self log:[NSString stringWithFormat:@"Mark %@ from %@", key, sender] details:details];
    }];
    return [LoggingUtil throttleOccurrenceLogger:r discardingAfterEventForDuration:0.5];
}
- (id<ConditionLogger>)getConditionLoggerForSender:(id)sender {
    return [AnonymousConditionLogger anonymousConditionLoggerWithLogNotice:^(NSString *text) {
      [self log:[NSString stringWithFormat:@"Notice from %@", sender] details:text];
    }
        andLogWarning:^(NSString *text) {
          [self log:[NSString stringWithFormat:@"Warning from %@", sender] details:text];
        }
        andLogError:^(NSString *text) {
          [self log:[NSString stringWithFormat:@"Error from %@", sender] details:text];
        }];
}

@end

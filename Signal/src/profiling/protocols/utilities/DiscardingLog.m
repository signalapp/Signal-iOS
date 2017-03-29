//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DiscardingLog.h"

@implementation DiscardingLog
+ (DiscardingLog *)discardingLog {
    return [DiscardingLog new];
}

- (id<OccurrenceLogger>)getOccurrenceLoggerForSender:(id)sender withKey:(NSString *)key {
    return self;
}
- (id<ConditionLogger>)getConditionLoggerForSender:(id)sender {
    return self;
}

- (id<ValueLogger>)getValueLoggerForValue:(id)valueIdentity from:(id)sender {
    return self;
}

- (void)logValue:(double)value {
}
- (void)markOccurrence:(id)details {
}
- (void)logError:(NSString *)text {
}
- (void)logNotice:(NSString *)text {
}
- (void)logWarning:(NSString *)text {
}

@end

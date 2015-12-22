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
- (id<JitterQueueNotificationReceiver>)jitterQueueNotificationReceiver {
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
- (void)notifyArrival:(uint16_t)sequenceNumber {
}
- (void)notifyDequeue:(uint16_t)sequenceNumber withRemainingEnqueuedItemCount:(NSUInteger)remainingCount {
}
- (void)notifyBadArrival:(uint16_t)sequenceNumber ofType:(enum JitterBadArrivalType)arrivalType {
}
- (void)notifyBadDequeueOfType:(enum JitterBadDequeueType)type {
}
- (void)notifyResyncFrom:(uint16_t)oldReadHeadSequenceNumber to:(uint16_t)newReadHeadSequenceNumber {
}
- (void)notifyDiscardOverflow:(uint16_t)discardedSequenceNumber
                resyncingFrom:(uint16_t)oldReadHeadSequenceNumber
                           to:(uint16_t)newReadHeadSequenceNumber {
}

@end

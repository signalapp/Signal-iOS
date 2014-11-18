#import "DiscardingLog.h"

@implementation DiscardingLog

#pragma mark Logging

- (id<OccurrenceLogger>)getOccurrenceLoggerForSender:(id)sender
                                             withKey:(NSString *)key {
    return self;
}

- (id<ConditionLogger>)getConditionLoggerForSender:(id)sender {
    return self;
}

- (id<JitterQueueNotificationReceiver>)jitterQueueNotificationReceiver {
    return self;
}

- (id<ValueLogger>)getValueLoggerForValue:(id)valueIdentity
                                     from:(id)sender {
    return self;
}

#pragma mark OccurrenceLogger

- (void)markOccurrence:(id)details {}

#pragma mark ConditionLogger

- (void)logNotice:(id)details {}

- (void)logWarning:(id)details {}

- (void)logError:(id)details {}

#pragma mark JitterQueueNotificationReceiver

- (void)notifyArrival:(uint16_t)sequenceNumber {}

- (void)notifyDequeue:(uint16_t)sequenceNumber withRemainingEnqueuedItemCount:(NSUInteger)remainingCount {}

- (void)notifyBadArrival:(uint16_t)sequenceNumber
                  ofType:(JitterBadArrivalType)arrivalType {}

- (void)notifyBadDequeueOfType:(JitterBadDequeueType)type {}

- (void)notifyResyncFrom:(uint16_t)oldReadHeadSequenceNumber
                      to:(uint16_t)newReadHeadSequenceNumber {}

- (void)notifyDiscardOverflow:(uint16_t)discardedSequenceNumber
                resyncingFrom:(uint16_t)oldReadHeadSequenceNumber
                           to:(uint16_t)newReadHeadSequenceNumber {}

#pragma mark ValueLogger

- (void)logValue:(double)value {}

@end

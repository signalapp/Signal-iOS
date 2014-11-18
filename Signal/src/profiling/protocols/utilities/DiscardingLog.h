#import <Foundation/Foundation.h>
#import "Logging.h"
#import "ConditionLogger.h"
#import "JitterQueue.h"

@interface DiscardingLog : NSObject <Logging, OccurrenceLogger, ConditionLogger, JitterQueueNotificationReceiver, ValueLogger>

// Conform to Logging
- (id<OccurrenceLogger>)getOccurrenceLoggerForSender:(id)sender
                                             withKey:(NSString*)key;
- (id<ConditionLogger>)getConditionLoggerForSender:(id)sender;
- (id<ValueLogger>)getValueLoggerForValue:(id)valueIdentity
                                     from:(id)sender;
- (id<JitterQueueNotificationReceiver>)jitterQueueNotificationReceiver;

// Conform to OccurrenceLogger
- (void)markOccurrence:(id)details;

// Conform to ConditionLogger
- (void)logNotice:(id)details;
- (void)logWarning:(id)details;
- (void)logError:(id)details;

// Conform to JitterQueueNotificationReceiver
- (void)notifyArrival:(uint16_t)sequenceNumber;
- (void)notifyDequeue:(uint16_t)sequenceNumber withRemainingEnqueuedItemCount:(NSUInteger)remainingCount;
- (void)notifyBadArrival:(uint16_t)sequenceNumber
                  ofType:(JitterBadArrivalType)arrivalType;
- (void)notifyBadDequeueOfType:(JitterBadDequeueType)type;
- (void)notifyResyncFrom:(uint16_t)oldReadHeadSequenceNumber
                      to:(uint16_t)newReadHeadSequenceNumber;
- (void)notifyDiscardOverflow:(uint16_t)discardedSequenceNumber
                resyncingFrom:(uint16_t)oldReadHeadSequenceNumber
                           to:(uint16_t)newReadHeadSequenceNumber;

// Conform to ValueLogger
- (void)logValue:(double)value;

@end

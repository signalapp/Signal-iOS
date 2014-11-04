#import <Foundation/Foundation.h>
#import "JitterQueue.h"
#import "Logging.h"

@interface CategorizingLogger : NSObject <Logging, JitterQueueNotificationReceiver>

- (void)addLoggingCallback:(void(^)(NSString* category, id details, NSUInteger index))callback;

// Conform to Logging
- (id<OccurrenceLogger>)getOccurrenceLoggerForSender:(id)sender
                                             withKey:(NSString*)key;
- (id<ConditionLogger>)getConditionLoggerForSender:(id)sender;
- (id<ValueLogger>)getValueLoggerForValue:(id)valueIdentity
                                     from:(id)sender;
- (id<JitterQueueNotificationReceiver>)jitterQueueNotificationReceiver;

// Conform to JitterQueueNotificationReceiver
- (void)notifyArrival:(uint16_t)sequenceNumber;
- (void)notifyDequeue:(uint16_t)sequenceNumber withRemainingEnqueuedItemCount:(NSUInteger)remainingCount;
- (void)notifyBadArrival:(uint16_t)sequenceNumber
                  ofType:(enum JitterBadArrivalType)arrivalType;
- (void)notifyBadDequeueOfType:(enum JitterBadDequeueType)type;
- (void)notifyResyncFrom:(uint16_t)oldReadHeadSequenceNumber
                      to:(uint16_t)newReadHeadSequenceNumber;
- (void)notifyDiscardOverflow:(uint16_t)discardedSequenceNumber
                resyncingFrom:(uint16_t)oldReadHeadSequenceNumber
                           to:(uint16_t)newReadHeadSequenceNumber;

@end

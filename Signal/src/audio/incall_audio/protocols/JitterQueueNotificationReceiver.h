#import <Foundation/Foundation.h>

enum JitterBadArrivalType {
    JitterBadArrivalType_Duplicate = 0, // for when two packets with the same sequence number arrive
    JitterBadArrivalType_Stale     = 1, // for when sequence number is behind read head
    JitterBadArrivalType_TooSoon   = 2  // for when sequence number is *way* ahead of read head
};
enum JitterBadDequeueType {
    JitterBadDequeueType_Desynced = 0, // for when so many lack-of-datas have accumulated that the read head can skip
    JitterBadDequeueType_Empty    = 1, // for when there's no data anywhere in the jitter queue
    JitterBadDequeueType_NoDataUnderReadHead =
        2 // for when there's data in the jitter queue, but it's ahead of the read head
};
@protocol JitterQueueNotificationReceiver <NSObject>
- (void)notifyArrival:(uint16_t)sequenceNumber;
- (void)notifyDequeue:(uint16_t)sequenceNumber withRemainingEnqueuedItemCount:(NSUInteger)remainingCount;
- (void)notifyBadArrival:(uint16_t)sequenceNumber ofType:(enum JitterBadArrivalType)arrivalType;
- (void)notifyBadDequeueOfType:(enum JitterBadDequeueType)type;
- (void)notifyResyncFrom:(uint16_t)oldReadHeadSequenceNumber to:(uint16_t)newReadHeadSequenceNumber;
- (void)notifyDiscardOverflow:(uint16_t)discardedSequenceNumber
                resyncingFrom:(uint16_t)oldReadHeadSequenceNumber
                           to:(uint16_t)newReadHeadSequenceNumber;
@end

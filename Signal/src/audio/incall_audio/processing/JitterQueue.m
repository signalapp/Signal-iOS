#import "Environment.h"
#import "JitterQueue.h"
#import "Util.h"

#define TRANSITIVE_SAFETY_RANGE 0x4000
#define READ_HEAD_MAX_QUEUE_AHEAD 0x1000
#define READ_HEAD_BAD_SPAN_THRESHOLD 0x100
#define MAXIMUM_JITTER_QUEUE_SIZE_BEFORE_DISCARDING 25

@implementation JitterQueue

+ (JitterQueue *)jitterQueue {
    JitterQueue *q  = [JitterQueue new];
    q->readHeadSpan = READ_HEAD_BAD_SPAN_THRESHOLD + 1;
    q->watchers     = [NSMutableArray array];
    [q registerWatcher:Environment.logging.jitterQueueNotificationReceiver];
    return q;
}

- (void)registerWatcher:(id<JitterQueueNotificationReceiver>)watcher {
    if (watcher == nil)
        return;
    [watchers addObject:watcher];
}

- (NSUInteger)count {
    return resultPriorityQueue.count;
}

- (bool)tryEnqueue:(EncodedAudioPacket *)audioPacket {
    ows_require(audioPacket != nil);

    uint16_t sequenceNumber = [audioPacket sequenceNumber];
    if (![self tryFitIntoSequence:sequenceNumber]) {
        return false;
    }

    [idsInJitterQueue addObject:@(sequenceNumber)];
    [resultPriorityQueue enqueue:audioPacket];
    if ([NumberUtil congruentDifferenceMod2ToThe16From:largestLatestEnqueued to:sequenceNumber] > 0) {
        largestLatestEnqueued = sequenceNumber;
    }

    for (id<JitterQueueNotificationReceiver> watcher in watchers) {
        [watcher notifyArrival:sequenceNumber];
    }

    [self discardExcess];

    return true;
}
- (bool)tryFitIntoSequence:(uint16_t)sequenceNumber {
    int16_t sequenceNumberRelativeToReadHead =
        [NumberUtil congruentDifferenceMod2ToThe16From:readHeadMin to:sequenceNumber];

    enum JitterBadArrivalType badArrivalType;
    if ([self tryForceSyncIfNecessary:sequenceNumber]) {
        return true;
    } else if (sequenceNumberRelativeToReadHead < 0) {
        badArrivalType = JitterBadArrivalType_Stale;
    } else if (sequenceNumberRelativeToReadHead > READ_HEAD_MAX_QUEUE_AHEAD) {
        badArrivalType = JitterBadArrivalType_TooSoon;
    } else if ([idsInJitterQueue containsObject:@(sequenceNumber)]) {
        badArrivalType = JitterBadArrivalType_Duplicate;
    } else {
        return true;
    }

    for (id<JitterQueueNotificationReceiver> watcher in watchers) {
        [watcher notifyBadArrival:sequenceNumber ofType:badArrivalType];
    }

    return false;
}
- (bool)tryForceSyncIfNecessary:(uint16_t)sequenceNumber {
    if (readHeadSpan <= READ_HEAD_BAD_SPAN_THRESHOLD)
        return false;

    if (resultPriorityQueue != nil) { // (only log resyncs, not the initial sync)
        for (id<JitterQueueNotificationReceiver> watcher in watchers) {
            [watcher notifyResyncFrom:readHeadMin to:sequenceNumber];
        }
    }

    readHeadMin           = sequenceNumber;
    largestLatestEnqueued = sequenceNumber;
    readHeadSpan          = 1;
    idsInJitterQueue      = [NSMutableSet set];
    resultPriorityQueue   = [JitterQueue makeCyclingPacketPriorityQueue];

    return true;
}
+ (PriorityQueue *)makeCyclingPacketPriorityQueue {
    return [PriorityQueue
        priorityQueueAscendingWithComparator:^NSComparisonResult(EncodedAudioPacket *obj1, EncodedAudioPacket *obj2) {
          int16_t d = [NumberUtil congruentDifferenceMod2ToThe16From:[obj2 sequenceNumber] to:[obj1 sequenceNumber]];
          requireState(abs(d) <= TRANSITIVE_SAFETY_RANGE);
          return [NumberUtil signOfInt32:d];
        }];
}
- (void)discardExcess {
    if (resultPriorityQueue.count <= MAXIMUM_JITTER_QUEUE_SIZE_BEFORE_DISCARDING)
        return;

    EncodedAudioPacket *discarded    = [resultPriorityQueue dequeue];
    uint16_t discardedSequenceNumber = [discarded sequenceNumber];
    [idsInJitterQueue removeObject:@(discardedSequenceNumber)];

    uint16_t oldReadHeadMax = readHeadMin + readHeadSpan - 1;
    readHeadMin             = [resultPriorityQueue.peek sequenceNumber];
    readHeadSpan            = 1;

    for (id<JitterQueueNotificationReceiver> e in watchers) {
        [e notifyDiscardOverflow:discardedSequenceNumber resyncingFrom:oldReadHeadMax to:readHeadMin];
    }
}

- (EncodedAudioPacket *)tryDequeue {
    if ([self checkReactIfOutOfSyncForDequeue] || [self checkReactIfEmptyForDequeue] ||
        [self checkReactIfNoDataUnderReadHeadForDequeue]) {
        return nil;
    }

    EncodedAudioPacket *result = [resultPriorityQueue dequeue];
    readHeadMin                = [result sequenceNumber] + 1;
    readHeadSpan               = 1;
    [idsInJitterQueue removeObject:@([result sequenceNumber])];

    for (id<JitterQueueNotificationReceiver> e in watchers) {
        [e notifyDequeue:[result sequenceNumber] withRemainingEnqueuedItemCount:idsInJitterQueue.count];
    }
    return result;
}
- (bool)checkReactIfOutOfSyncForDequeue {
    bool isOutOfSync = readHeadSpan > READ_HEAD_BAD_SPAN_THRESHOLD;
    if (isOutOfSync) {
        for (id<JitterQueueNotificationReceiver> watcher in watchers) {
            [watcher notifyBadDequeueOfType:JitterBadDequeueType_Desynced];
        }
    }
    return isOutOfSync;
}
- (bool)checkReactIfEmptyForDequeue {
    bool isEmpty = resultPriorityQueue.count == 0;
    if (isEmpty) {
        readHeadSpan += 1;
        for (id<JitterQueueNotificationReceiver> watcher in watchers) {
            [watcher notifyBadDequeueOfType:JitterBadDequeueType_Empty];
        }
    }
    return isEmpty;
}
- (bool)checkReactIfNoDataUnderReadHeadForDequeue {
    EncodedAudioPacket *result = resultPriorityQueue.peek;
    int16_t d                  = [NumberUtil congruentDifferenceMod2ToThe16From:readHeadMin to:[result sequenceNumber]];
    bool notUnderHead          = d < 0 || d >= readHeadSpan;
    if (notUnderHead) {
        readHeadSpan += 1;
        for (id<JitterQueueNotificationReceiver> watcher in watchers) {
            [watcher notifyBadDequeueOfType:JitterBadDequeueType_NoDataUnderReadHead];
        }
    }
    return notUnderHead;
}

- (int16_t)currentBufferDepth {
    if (readHeadSpan > READ_HEAD_BAD_SPAN_THRESHOLD)
        return 0;
    return [NumberUtil congruentDifferenceMod2ToThe16From:readHeadMin + readHeadSpan - 1 to:largestLatestEnqueued];
}

@end

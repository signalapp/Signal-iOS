#import "JitterQueue.h"
#import "Util.h"
#import "Environment.h"

#define TRANSITIVE_SAFETY_RANGE 0x4000
#define READ_HEAD_MAX_QUEUE_AHEAD 0x1000
#define READ_HEAD_BAD_SPAN_THRESHOLD 0x100
#define MAXIMUM_JITTER_QUEUE_SIZE_BEFORE_DISCARDING 25

@interface JitterQueue ()

@property (strong, nonatomic) PriorityQueue* resultPriorityQueue;
@property (strong, nonatomic) NSMutableSet* idsInJitterQueue;
@property (strong, nonatomic) NSMutableArray* watchers;
@property (nonatomic) uint16_t readHeadMin;
@property (nonatomic) uint16_t readHeadSpan;
@property (nonatomic) uint16_t largestLatestEnqueued;

@end

@implementation JitterQueue

- (instancetype)init {
    self = [super init];
	
    if (self) {
        self.readHeadSpan = READ_HEAD_BAD_SPAN_THRESHOLD + 1;
        self.watchers = [[NSMutableArray alloc] init];
        [self registerWatcher:Environment.logging.jitterQueueNotificationReceiver];
    }
    
    return self;
}

- (void)registerWatcher:(id<JitterQueueNotificationReceiver>)watcher {
    if (watcher == nil) return;
    [self.watchers addObject:watcher];
}

- (NSUInteger)count {
    return self.resultPriorityQueue.count;
}

- (bool)tryEnqueue:(EncodedAudioPacket*)audioPacket {
    require(audioPacket != nil);
    
    uint16_t sequenceNumber = [audioPacket sequenceNumber];
    if (![self tryFitIntoSequence:sequenceNumber]) {
        return false;
    }
    
    [self.idsInJitterQueue addObject:@(sequenceNumber)];
    [self.resultPriorityQueue enqueue:audioPacket];
    if ([NumberUtil congruentDifferenceMod2ToThe16From:self.largestLatestEnqueued to:sequenceNumber] > 0) {
        self.largestLatestEnqueued = sequenceNumber;
    }

    for (id<JitterQueueNotificationReceiver> watcher in self.watchers) {
        [watcher notifyArrival:sequenceNumber];
    }

    [self discardExcess];

    return true;
}

- (bool)tryFitIntoSequence:(uint16_t)sequenceNumber {
    int16_t sequenceNumberRelativeToReadHead = [NumberUtil congruentDifferenceMod2ToThe16From:self.readHeadMin to:sequenceNumber];
    
    JitterBadArrivalType badArrivalType;
    if ([self tryForceSyncIfNecessary:sequenceNumber]) {
        return true;
    } else if (sequenceNumberRelativeToReadHead < 0) {
        badArrivalType = JitterBadArrivalType_Stale;
    } else if (sequenceNumberRelativeToReadHead > READ_HEAD_MAX_QUEUE_AHEAD) {
        badArrivalType = JitterBadArrivalType_TooSoon;
    } else if ([self.idsInJitterQueue containsObject:@(sequenceNumber)]) {
        badArrivalType = JitterBadArrivalType_Duplicate;
    } else {
        return true;
    }
    
    for (id<JitterQueueNotificationReceiver> watcher in self.watchers) {
        [watcher notifyBadArrival:sequenceNumber ofType:badArrivalType];
    }
    
    return false;
}

- (bool)tryForceSyncIfNecessary:(uint16_t)sequenceNumber {
    if (self.readHeadSpan <= READ_HEAD_BAD_SPAN_THRESHOLD) return false;
    
    if (self.resultPriorityQueue != nil) { // (only log resyncs, not the initial sync)
        for (id<JitterQueueNotificationReceiver> watcher in self.watchers) {
            [watcher notifyResyncFrom:self.readHeadMin to:sequenceNumber];
        }
    }
    
    self.readHeadMin = sequenceNumber;
    self.largestLatestEnqueued = sequenceNumber;
    self.readHeadSpan = 1;
    self.idsInJitterQueue = [[NSMutableSet alloc] init];
    self.resultPriorityQueue = [JitterQueue makeCyclingPacketPriorityQueue];
    
    return true;
}

+ (PriorityQueue*)makeCyclingPacketPriorityQueue {
    return [[PriorityQueue alloc] initAscendingWithComparator:^NSComparisonResult(EncodedAudioPacket* obj1, EncodedAudioPacket* obj2) {
        int16_t d = [NumberUtil congruentDifferenceMod2ToThe16From:[obj2 sequenceNumber]
                                                                to:[obj1 sequenceNumber]];
        requireState(abs(d) <= TRANSITIVE_SAFETY_RANGE);
        return [NumberUtil signOfInt32:d];
    }];
}

- (void)discardExcess {
    if (self.resultPriorityQueue.count <= MAXIMUM_JITTER_QUEUE_SIZE_BEFORE_DISCARDING) return;
    
    EncodedAudioPacket* discarded = [self.resultPriorityQueue dequeue];
    uint16_t discardedSequenceNumber = [discarded sequenceNumber];
    [self.idsInJitterQueue removeObject:@(discardedSequenceNumber)];
    
    uint16_t oldReadHeadMax = self.readHeadMin + self.readHeadSpan - 1;
    self.readHeadMin = [self.resultPriorityQueue.peek sequenceNumber];
    self.readHeadSpan = 1;
    
    for (id<JitterQueueNotificationReceiver> e in self.watchers) {
        [e notifyDiscardOverflow:discardedSequenceNumber
                   resyncingFrom:oldReadHeadMax
                              to:self.readHeadMin];
    }
}

- (EncodedAudioPacket*)tryDequeue {
    if ([self checkReactIfOutOfSyncForDequeue]
        || [self checkReactIfEmptyForDequeue]
        || [self checkReactIfNoDataUnderReadHeadForDequeue]) {
        
        return nil;
    }
    
    EncodedAudioPacket* result = [self.resultPriorityQueue dequeue];
    self.readHeadMin = [result sequenceNumber]+1;
    self.readHeadSpan = 1;
    [self.idsInJitterQueue removeObject:@([result sequenceNumber])];
    
    for (id<JitterQueueNotificationReceiver> e in self.watchers) {
        [e notifyDequeue:[result sequenceNumber] withRemainingEnqueuedItemCount:self.idsInJitterQueue.count];
    }
    return result;
}

- (bool)checkReactIfOutOfSyncForDequeue {
    bool isOutOfSync = self.readHeadSpan > READ_HEAD_BAD_SPAN_THRESHOLD;
    if (isOutOfSync) {
        for (id<JitterQueueNotificationReceiver> watcher in self.watchers) {
            [watcher notifyBadDequeueOfType:JitterBadDequeueType_Desynced];
        }
    }
    return isOutOfSync;
}

- (bool)checkReactIfEmptyForDequeue {
    bool isEmpty = self.resultPriorityQueue.count == 0;
    if (isEmpty) {
        self.readHeadSpan += 1;
        for (id<JitterQueueNotificationReceiver> watcher in self.watchers) {
            [watcher notifyBadDequeueOfType:JitterBadDequeueType_Empty];
        }
    }
    return isEmpty;
}

- (bool)checkReactIfNoDataUnderReadHeadForDequeue {
    EncodedAudioPacket* result = self.resultPriorityQueue.peek;
    int16_t d = [NumberUtil congruentDifferenceMod2ToThe16From:self.readHeadMin
                                                            to:[result sequenceNumber]];
    bool notUnderHead = d < 0 || d >= self.readHeadSpan;
    if (notUnderHead) {
        self.readHeadSpan += 1;
        for (id<JitterQueueNotificationReceiver> watcher in self.watchers) {
            [watcher notifyBadDequeueOfType:JitterBadDequeueType_NoDataUnderReadHead];
        }
    }
    return notUnderHead;
}

- (int16_t)currentBufferDepth {
    if (self.readHeadSpan > READ_HEAD_BAD_SPAN_THRESHOLD) return 0;
    return [NumberUtil congruentDifferenceMod2ToThe16From:self.readHeadMin + self.readHeadSpan - 1 to:self.largestLatestEnqueued];
}

@end

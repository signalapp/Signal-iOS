#import "CategorizingLogger.h"
#import "AnonymousOccurrenceLogger.h"
#import "AnonymousConditionLogger.h"
#import "AnonymousValueLogger.h"
#import "LoggingUtil.h"

@interface CategorizingLogger ()

@property (strong, nonatomic) NSMutableArray* callbacks;
@property (strong, nonatomic) NSMutableDictionary* indexDic;

@end

@implementation CategorizingLogger

#pragma mark Private methods

- (NSMutableArray*)callbacks {
    if (!_callbacks) {
        _callbacks = [[NSMutableArray alloc] init];
    }
    return _callbacks;
}

- (NSMutableDictionary*)indexDic {
    if (!_indexDic) {
        _indexDic = [[NSMutableDictionary alloc] init];
    }
    return _indexDic;
}

- (void)log:(NSString*)category
    details:(id)details {
    NSNumber* index = self.indexDic[category];
    if (index == nil) {
        index = @(self.indexDic.count);
        self.indexDic[category] = index;
    }
    
    NSUInteger x = [index unsignedIntegerValue];
    for (void (^callback)(NSString* category, id details, NSUInteger index) in self.callbacks) {
        callback(category, details, x);
    }
}

#pragma mark Public methods

- (void)addLoggingCallback:(void(^)(NSString* category, id details, NSUInteger index))callback {
    [self.callbacks addObject:[callback copy]];
}

#pragma mark Logging

- (id<ValueLogger>)getValueLoggerForValue:(id)valueIdentity
                                     from:(id)sender {
    id<ValueLogger> r = [[AnonymousValueLogger alloc] initWithLogValue:^(double value) {
        [self log:[NSString stringWithFormat:@"Value %@ from %@", valueIdentity, sender] details:@(value)];
    }];
    return [LoggingUtil throttleValueLogger:r discardingAfterEventForDuration:0.5];
}

- (id<OccurrenceLogger>)getOccurrenceLoggerForSender:(id)sender
                                             withKey:(NSString*)key {
    id<OccurrenceLogger> r = [[AnonymousOccurrenceLogger alloc] initWithMarker:^(id details){
        [self log:[NSString stringWithFormat:@"Mark %@ from %@", key, sender] details:details];
    }];
    return [LoggingUtil throttleOccurrenceLogger:r discardingAfterEventForDuration:0.5];
}

- (id<ConditionLogger>)getConditionLoggerForSender:(id)sender {
    return [[AnonymousConditionLogger alloc] initWithLogNotice:^(NSString *text) {
        [self log:[NSString stringWithFormat:@"Notice from %@", sender] details:text];
    } andLogWarning:^(NSString *text) {
        [self log:[NSString stringWithFormat:@"Warning from %@", sender] details:text];
    } andLogError:^(NSString *text) {
        [self log:[NSString stringWithFormat:@"Error from %@", sender] details:text];
    }];
}

- (id<JitterQueueNotificationReceiver>)jitterQueueNotificationReceiver {
    return self;
}

#pragma mark JitterQueueNotificationReceiver

- (void)notifyCreated {
    [self log:@"JitterQueue created" details:nil];
}

- (void)notifyArrival:(uint16_t)sequenceNumber {
    [self log:@"JitterQueue arrival" details:[NSString stringWithFormat:@"sequence: %d", sequenceNumber]];
}

- (void)notifyDequeue:(uint16_t)sequenceNumber withRemainingEnqueuedItemCount:(NSUInteger)remainingCount {
    [self log:@"JitterQueue dequeue" details:[NSString stringWithFormat:@"sequence: %d, remaining: %lu", sequenceNumber, (unsigned long)remainingCount]];
}

- (void)notifyBadArrival:(uint16_t)sequenceNumber
                  ofType:(JitterBadArrivalType)arrivalType {
    [self log:@"JitterQueue bad arrival" details:[NSString stringWithFormat:@"sequence: %d, arrival type: %ldd", sequenceNumber, arrivalType]];
}

- (void)notifyBadDequeueOfType:(JitterBadDequeueType)type {
    [self log:@"JitterQueue bad dequeue" details:[NSString stringWithFormat:@"type: %ld", type]];
}

- (void)notifyResyncFrom:(uint16_t)oldReadHeadSequenceNumber
                      to:(uint16_t)newReadHeadSequenceNumber {
    [self log:@"JitterQueue resync" details:[NSString stringWithFormat:@"from: %d, to: %d", oldReadHeadSequenceNumber, newReadHeadSequenceNumber]];
}

- (void)notifyDiscardOverflow:(uint16_t)discardedSequenceNumber
                resyncingFrom:(uint16_t)oldReadHeadSequenceNumber
                           to:(uint16_t)newReadHeadSequenceNumber {
    [self log:@"JitterQueue discard overflow" details:[NSString stringWithFormat:@"discarded: %d, from: %d, to: %d", discardedSequenceNumber, oldReadHeadSequenceNumber, newReadHeadSequenceNumber]];
}

@end

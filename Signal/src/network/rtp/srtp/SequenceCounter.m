#import "SequenceCounter.h"

const int64_t ShortRange = ((int64_t)1) << 16;

@implementation SequenceCounter
+(SequenceCounter*) sequenceCounter {
    return [SequenceCounter new];
}
-(int64_t)convertNext:(uint16_t)nextShortId {
    int64_t delta = (int64_t)nextShortId - (int64_t)prevShortId;
    if (delta > INT16_MAX) delta -= ShortRange;
    if (delta < INT16_MIN) delta += ShortRange;
    int64_t nextLongId = prevLongId + delta;
    
    prevShortId = nextShortId;
    prevLongId = nextLongId;
    return nextLongId;
}
@end

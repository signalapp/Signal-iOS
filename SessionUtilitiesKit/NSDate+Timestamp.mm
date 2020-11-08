#import "NSDate+Timestamp.h"
#import <chrono>

NS_ASSUME_NONNULL_BEGIN

@implementation NSDate (Session)

+ (uint64_t)millisecondTimestamp
{
    return (uint64_t)(std::chrono::system_clock::now().time_since_epoch() / std::chrono::milliseconds(1));
}

@end

NS_ASSUME_NONNULL_END


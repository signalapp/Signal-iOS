#import <Foundation/Foundation.h>
#import "ConditionLogger.h"
#import "JitterQueue.h"
#import "Logging.h"

@interface DiscardingLog
    : NSObject <Logging, OccurrenceLogger, ConditionLogger, JitterQueueNotificationReceiver, ValueLogger>
+ (DiscardingLog *)discardingLog;
@end

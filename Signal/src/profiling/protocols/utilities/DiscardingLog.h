#import <Foundation/Foundation.h>
#import "Logging.h"
#import "ConditionLogger.h"
#import "JitterQueue.h"

@interface DiscardingLog : NSObject<Logging, OccurrenceLogger, ConditionLogger, JitterQueueNotificationReceiver, ValueLogger>
+(DiscardingLog*) discardingLog;
@end

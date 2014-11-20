#import <Foundation/Foundation.h>
#import "JitterQueue.h"
#import "Logging.h"

@interface CategorizingLogger : NSObject <Logging, JitterQueueNotificationReceiver>

- (instancetype)init;

- (void)addLoggingCallback:(void(^)(NSString* category, id details, NSUInteger index))callback;

@end

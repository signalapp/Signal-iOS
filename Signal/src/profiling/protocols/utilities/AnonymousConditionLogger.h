#import <Foundation/Foundation.h>
#import "ConditionLogger.h"

@interface AnonymousConditionLogger : NSObject <ConditionLogger>

@property (nonatomic, readonly, copy) void (^logNoticeBlock)(id details);
@property (nonatomic, readonly, copy) void (^logWarningBlock)(id details);
@property (nonatomic, readonly, copy) void (^logErrorBlock)(id details);

+ (AnonymousConditionLogger *)anonymousConditionLoggerWithLogNotice:(void (^)(id details))logNotice
                                                      andLogWarning:(void (^)(id details))logWarning
                                                        andLogError:(void (^)(id details))logError;

@end

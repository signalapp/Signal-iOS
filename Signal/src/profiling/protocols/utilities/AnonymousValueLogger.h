#import <Foundation/Foundation.h>
#import "ValueLogger.h"

@interface AnonymousValueLogger : NSObject <ValueLogger>

@property (nonatomic, readonly, copy) void (^logValueBlock)(double value);

+ (AnonymousValueLogger *)anonymousValueLogger:(void (^)(double value))logValue;

@end

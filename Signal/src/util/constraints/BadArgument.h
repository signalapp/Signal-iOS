#import <Foundation/Foundation.h>

@interface BadArgument : NSException
+(BadArgument*) new:(NSString*)reason;
+(void)raise:(NSString *)message;
@end

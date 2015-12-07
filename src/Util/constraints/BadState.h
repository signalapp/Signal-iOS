#import <Foundation/Foundation.h>

@interface BadState : NSException
+(void)raise:(NSString *)message;
@end

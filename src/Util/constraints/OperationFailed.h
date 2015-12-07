#import <Foundation/Foundation.h>

@interface OperationFailed : NSException
+(OperationFailed*) new:(NSString*)reason;
+(void)raise:(NSString *)message;
@end

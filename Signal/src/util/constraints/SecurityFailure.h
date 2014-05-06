#import <Foundation/Foundation.h>
#import "OperationFailed.h"

@interface SecurityFailure : OperationFailed
+(SecurityFailure*) new:(SecurityFailure*)reason;
+(void)raise:(NSString *)message;
@end

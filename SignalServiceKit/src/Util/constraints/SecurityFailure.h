//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OperationFailed.h"

@interface SecurityFailure : OperationFailed
+(SecurityFailure*) new:(SecurityFailure*)reason;
+(void)raise:(NSString *)message;
@end

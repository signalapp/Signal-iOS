//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface OperationFailed : NSException
+(OperationFailed*) new:(NSString*)reason;
+(void)raise:(NSString *)message;
@end

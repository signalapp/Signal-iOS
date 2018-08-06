//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface BadArgument : NSException
+(BadArgument*) new:(NSString*)reason;
+(void)raise:(NSString *)message;
@end

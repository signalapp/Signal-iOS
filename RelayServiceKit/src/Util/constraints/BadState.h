//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface BadState : NSException
+(void)raise:(NSString *)message;
@end

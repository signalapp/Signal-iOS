//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

@class SMKUDAccessKey;

@interface TSRequest (UD)

- (void)useUDAuth:(SMKUDAccessKey *)udAccessKey;

@end

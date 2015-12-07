//
//  TSInvalidIdentityKeyErrorMessage.h
//  Signal
//
//  Created by Frederic Jacobs on 15/02/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"

@interface TSInvalidIdentityKeyErrorMessage : TSErrorMessage

- (void)acceptNewIdentityKey;
- (NSString *)newIdentityKey;

@end

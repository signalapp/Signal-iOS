//
//  TSMessagesManager+callRecorder.h
//  Signal
//
//  Created by Frederic Jacobs on 26/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesManager.h"
#import "TSCall.h"

@interface TSMessagesManager (callRecorder)

- (void)storePhoneCall:(TSCall*)call;

@end

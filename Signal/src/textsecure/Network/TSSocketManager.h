//
//  TSSocketManager.h
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 17/05/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SRWebSocket.h>

@interface TSSocketManager : NSObject <SRWebSocketDelegate>

+ (void)becomeActive;
+ (void)resignActivity;

@end

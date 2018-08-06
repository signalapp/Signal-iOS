//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import <SocketRocket/SRSecurityPolicy.h>

@interface OWSWebsocketSecurityPolicy : SRSecurityPolicy

+ (instancetype)sharedPolicy;

@end

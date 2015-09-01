//
//  AFSecurityPolicyNone.h
//  Signal
//
//  Created by Fred on 01/09/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.
//

#import "AFSecurityPolicy.h"
#import <SocketRocket/SRWebSocket.h>

@interface AFSecurityOWSPolicy : AFSecurityPolicy <CertificateVerifier>

+ (instancetype)OWS_PinningPolicy;

@end

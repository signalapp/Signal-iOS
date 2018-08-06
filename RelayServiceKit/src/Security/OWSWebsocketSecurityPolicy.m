//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSWebsocketSecurityPolicy.h"
#import "OWSHTTPSecurityPolicy.h"
#import <SocketRocket/SRSecurityPolicy.h>

@implementation OWSWebsocketSecurityPolicy

+ (instancetype)sharedPolicy {
    static OWSWebsocketSecurityPolicy *websocketSecurityPolicy = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // We use our own CA
        websocketSecurityPolicy = [[self alloc] initWithCertificateChainValidationEnabled:NO];
#pragma clang diagnostic pop
    });
    return websocketSecurityPolicy;
}

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust forDomain:(NSString *)domain {
  // Delegate server trust to our existing HTTP policy.
  return [[OWSHTTPSecurityPolicy sharedPolicy] evaluateServerTrust:serverTrust forDomain:domain];
}

@end

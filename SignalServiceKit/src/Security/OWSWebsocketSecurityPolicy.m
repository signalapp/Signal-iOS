//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSWebsocketSecurityPolicy.h"

#import <SocketRocket/SRSecurityPolicy.h>
#import "OWSHTTPSecurityPolicy.h"

@implementation OWSWebsocketSecurityPolicy

+ (instancetype)sharedPolicy {
    static OWSWebsocketSecurityPolicy *websocketSecurityPolicy = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        websocketSecurityPolicy = [[self alloc] initWithCertificateChainValidationEnabled:NO];
    });
    return websocketSecurityPolicy;
}

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust forDomain:(NSString *)domain {
  // Delegate server trust to our existing HTTP policy.
  return [[OWSHTTPSecurityPolicy sharedPolicy] evaluateServerTrust:serverTrust forDomain:domain];
}

@end

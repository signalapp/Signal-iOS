#import "SecureEndPoint.h"
#import "Util.h"
#import "DnsManager.h"

@implementation SecureEndPoint
@synthesize certificate, hostNameEndPoint;

+(SecureEndPoint*) secureEndPointForHost:(HostNameEndPoint*)host
                 identifiedByCertificate:(Certificate*)certificate {
    
    require(host != nil);
    require(certificate != nil);
    
    return [self secureEndPointForHost:host
               identifiedByCertificate:certificate
      withOptionalMoreSpecificEndPoint:nil];
}

+(SecureEndPoint*) secureEndPointForHost:(HostNameEndPoint*)host
                 identifiedByCertificate:(Certificate*)certificate
        withOptionalMoreSpecificEndPoint:(id<NetworkEndPoint>)optionalMoreSpecificEndPoint {
    
    require(host != nil);
    require(certificate != nil);
    
    SecureEndPoint* s = [SecureEndPoint new];
    s->hostNameEndPoint = host;
    s->certificate = certificate;
    s->optionalMoreSpecificEndPoint = optionalMoreSpecificEndPoint;
    return s;
}

-(StreamPair *)createStreamPair {
    if (optionalMoreSpecificEndPoint != nil) {
        return [optionalMoreSpecificEndPoint createStreamPair];
    }
    
    return [hostNameEndPoint createStreamPair];
}

-(void) handleStreamsOpened:(StreamPair *)streamPair {
    [[streamPair inputStream] setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
                                   forKey:NSStreamSocketSecurityLevelKey];
    
    [[streamPair outputStream] setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
                                    forKey:NSStreamSocketSecurityLevelKey];
    
    NSDictionary *settings = [[NSDictionary alloc] initWithObjectsAndKeys:
                              [NSNumber numberWithBool:NO], kCFStreamSSLValidatesCertificateChain,
                              hostNameEndPoint.hostname, kCFStreamSSLPeerName,
                              nil];
    
    CFReadStreamSetProperty((CFReadStreamRef)[streamPair inputStream],
                            kCFStreamPropertySSLSettings,
                            (CFTypeRef)settings);
    
    CFWriteStreamSetProperty((CFWriteStreamRef)[streamPair outputStream],
                             kCFStreamPropertySSLSettings,
                             (CFTypeRef)settings);
}

-(void) authenticateSslStream:(StreamPair*)streamPair {
    
    SecTrustRef trust = (__bridge SecTrustRef)[[streamPair outputStream] propertyForKey:(__bridge NSString*)kCFStreamPropertySSLPeerTrust];
    
    checkOperation(SecTrustGetCertificateCount(trust) > 0);
    
    [certificate setAsAnchorForTrust:trust];
    SecTrustResultType trustResult = kSecTrustResultInvalid;
    OSStatus evalResult = SecTrustEvaluate(trust, &trustResult);
    checkSecurityOperation(evalResult == 0,
                           ([NSString stringWithFormat:@"NetworkStream: SecTrustEvaluate failed with error code: %d", (int)evalResult]));
    checkSecurityOperation(trustResult != kSecTrustResultProceed,
                           @"Unexpected: User approved certificate somehow? Failing safe.");
    checkSecurityOperation(trustResult == kSecTrustResultUnspecified,
                           ([NSString stringWithFormat:@"NetworkStream: SecTrustEvaluate returned bad result: %u.", trustResult]));
}

-(Future *)asyncHandleStreamsConnected:(StreamPair *)streamPair {
    require(streamPair != nil);
    
    @try {
        [self authenticateSslStream:streamPair];
        return [Future finished:@YES];
    } @catch (OperationFailed* ex) {
        return [Future failed:ex];
    }
}

-(Future*) asyncResolveToSpecificEndPointsUnlessCancelled:(id<CancelToken>)unlessCancelledToken {
    Future* futureResolvedLocations = [hostNameEndPoint asyncResolveToSpecificEndPointsUnlessCancelled:unlessCancelledToken];
    
    return [futureResolvedLocations then:^(NSArray* specificEndPoints) {
        return [specificEndPoints map:^(id<NetworkEndPoint> specificEndPoint) {
            return [SecureEndPoint secureEndPointForHost:hostNameEndPoint
                                 identifiedByCertificate:certificate
                        withOptionalMoreSpecificEndPoint:specificEndPoint];
        }];
    }];
}

-(NSString*) description {
    if (optionalMoreSpecificEndPoint == nil) {
        return [NSString stringWithFormat:@"Host: %@, Certificate: %@)",
                hostNameEndPoint,
                certificate];
    }
    
    return [NSString stringWithFormat:@"Host: %@ (resolved to %@), Certificate: %@)",
            hostNameEndPoint,
            optionalMoreSpecificEndPoint,
            certificate];
}

@end

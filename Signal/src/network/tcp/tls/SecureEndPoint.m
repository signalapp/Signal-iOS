#import "SecureEndPoint.h"
#import "Util.h"

@implementation SecureEndPoint
@synthesize certificate, hostNameEndPoint;

+(SecureEndPoint*) secureEndPointForHost:(HostNameEndPoint*)host
                 identifiedByCertificate:(Certificate*)certificate {
    
    ows_require(host != nil);
    ows_require(certificate != nil);
    
    return [self secureEndPointForHost:host
               identifiedByCertificate:certificate
      withOptionalMoreSpecificEndPoint:nil];
}

+(SecureEndPoint*) secureEndPointForHost:(HostNameEndPoint*)host
                 identifiedByCertificate:(Certificate*)certificate
        withOptionalMoreSpecificEndPoint:(id<NetworkEndPoint>)optionalMoreSpecificEndPoint {
    
    ows_require(host != nil);
    ows_require(certificate != nil);
    
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
    [[streamPair inputStream] setProperty:(__bridge id)CFSTR("kNSStreamSocketSecurityLevelTLSv1_2")
                                   forKey:NSStreamSocketSecurityLevelKey];
    
    [[streamPair outputStream] setProperty:(__bridge id)CFSTR("kNSStreamSocketSecurityLevelTLSv1_2")
                                    forKey:NSStreamSocketSecurityLevelKey];
    
    NSDictionary *settings = @{(id)kCFStreamSSLValidatesCertificateChain: @NO,
                               (id)kCFStreamSSLPeerName: hostNameEndPoint.hostname};
    
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

-(TOCFuture*)asyncHandleStreamsConnected:(StreamPair *)streamPair {
    ows_require(streamPair != nil);
    
    @try {
        [self authenticateSslStream:streamPair];
        return [TOCFuture futureWithResult:@YES];
    } @catch (OperationFailed* ex) {
        return [TOCFuture futureWithFailure:ex];
    }
}

-(TOCFuture*) asyncResolveToSpecificEndPointsUnlessCancelled:(TOCCancelToken*)unlessCancelledToken {
    TOCFuture* futureResolvedLocations = [hostNameEndPoint asyncResolveToSpecificEndPointsUnlessCancelled:unlessCancelledToken];
    
    return [futureResolvedLocations thenTry:^(NSArray* specificEndPoints) {
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

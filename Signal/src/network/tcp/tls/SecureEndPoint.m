#import "SecureEndPoint.h"
#import "Util.h"
#import "DNSManager.h"

@interface SecureEndPoint ()

@property (strong, nonatomic) id<NetworkEndPoint> optionalMoreSpecificEndPoint;
@property (strong, readwrite, nonatomic) Certificate* certificate;
@property (strong, readwrite, nonatomic) HostNameEndPoint* hostNameEndPoint;

@end

@implementation SecureEndPoint

- (instancetype)initWithHost:(HostNameEndPoint*)host
     identifiedByCertificate:(Certificate*)certificate {
    
    require(host != nil);
    require(certificate != nil);
    
    return [self initWithHost:host identifiedByCertificate:certificate withOptionalMoreSpecificEndPoint:nil];
}

- (instancetype)initWithHost:(HostNameEndPoint*)host
     identifiedByCertificate:(Certificate*)certificate
withOptionalMoreSpecificEndPoint:(id<NetworkEndPoint>)optionalMoreSpecificEndPoint {
    
    if (self = [super init]) {
        require(host != nil);
        require(certificate != nil);
        
        self.hostNameEndPoint = host;
        self.certificate = certificate;
        self.optionalMoreSpecificEndPoint = optionalMoreSpecificEndPoint;
    }
    
    return self;
}

- (StreamPair*)createStreamPair {
    if (self.optionalMoreSpecificEndPoint != nil) {
        return [self.optionalMoreSpecificEndPoint createStreamPair];
    }
    
    return [self.hostNameEndPoint createStreamPair];
}

- (void)handleStreamsOpened:(StreamPair*)streamPair {
    [streamPair.inputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
                                 forKey:NSStreamSocketSecurityLevelKey];
    
    [streamPair.outputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
                                  forKey:NSStreamSocketSecurityLevelKey];
    
    NSDictionary *settings = @{(id)kCFStreamSSLValidatesCertificateChain: @NO,
                               (id)kCFStreamSSLPeerName: self.hostNameEndPoint.hostname};
    
    CFReadStreamSetProperty((CFReadStreamRef)streamPair.inputStream,
                            kCFStreamPropertySSLSettings,
                            (CFTypeRef)settings);
    
    CFWriteStreamSetProperty((CFWriteStreamRef)streamPair.outputStream,
                             kCFStreamPropertySSLSettings,
                             (CFTypeRef)settings);
}

- (void)authenticateSSLStream:(StreamPair*)streamPair {
    
    SecTrustRef trust = (__bridge SecTrustRef)[streamPair.outputStream propertyForKey:(__bridge NSString*)kCFStreamPropertySSLPeerTrust];
    
    checkOperation(SecTrustGetCertificateCount(trust) > 0);
    
    [self.certificate setAsAnchorForTrust:trust];
    SecTrustResultType trustResult = kSecTrustResultInvalid;
    OSStatus evalResult = SecTrustEvaluate(trust, &trustResult);
    checkSecurityOperation(evalResult == 0,
                           ([NSString stringWithFormat:@"NetworkStream: SecTrustEvaluate failed with error code: %d", (int)evalResult]));
    checkSecurityOperation(trustResult != kSecTrustResultProceed,
                           @"Unexpected: User approved certificate somehow? Failing safe.");
    checkSecurityOperation(trustResult == kSecTrustResultUnspecified,
                           ([NSString stringWithFormat:@"NetworkStream: SecTrustEvaluate returned bad result: %u.", trustResult]));
}

- (TOCFuture*)asyncHandleStreamsConnected:(StreamPair*)streamPair {
    require(streamPair != nil);
    
    @try {
        [self authenticateSSLStream:streamPair];
        return [TOCFuture futureWithResult:@YES];
    } @catch (OperationFailed* ex) {
        return [TOCFuture futureWithFailure:ex];
    }
}

- (TOCFuture*)asyncResolveToSpecificEndPointsUnlessCancelled:(TOCCancelToken*)unlessCancelledToken {
    TOCFuture* futureResolvedLocations = [self.hostNameEndPoint asyncResolveToSpecificEndPointsUnlessCancelled:unlessCancelledToken];
    
    return [futureResolvedLocations thenTry:^(NSArray* specificEndPoints) {
        return [specificEndPoints map:^(id<NetworkEndPoint> specificEndPoint) {
            return [[SecureEndPoint alloc] initWithHost:self.hostNameEndPoint
                                identifiedByCertificate:self.certificate
                       withOptionalMoreSpecificEndPoint:specificEndPoint];
        }];
    }];
}

- (NSString*)description {
    if (!self.optionalMoreSpecificEndPoint) {
        return [NSString stringWithFormat:@"Host: %@, Certificate: %@)",
                self.hostNameEndPoint,
                self.certificate];
    }
    
    return [NSString stringWithFormat:@"Host: %@ (resolved to %@), Certificate: %@)",
            self.hostNameEndPoint,
            self.optionalMoreSpecificEndPoint,
            self.certificate];
}

@end

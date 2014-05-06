#import "Certificate.h"
#import "Util.h"

@implementation Certificate

+(Certificate*) certificateFromTrust:(SecTrustRef)trust
                             atIndex:(CFIndex)index {
    require(trust != nil);
    require(index >= 0);
    
    SecCertificateRef cert = SecTrustGetCertificateAtIndex(trust, index);
    checkOperation(cert != nil);
    CFRetain(cert);
    
    Certificate* instance = [Certificate new];
    instance->secCertificateRef = cert;
    return instance;
}

+(Certificate*) certificateFromResourcePath:(NSString*)resourcePath
                                     ofType:(NSString*)resourceType {
    require(resourcePath != nil);
    require(resourceType != nil);
    
    NSString *certPath = [[NSBundle mainBundle] pathForResource:resourcePath ofType:resourceType];
    NSData *certData = [[NSData alloc] initWithContentsOfFile:certPath];
    checkOperation(certData != nil);

    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    checkOperation(cert != nil);
    
    Certificate* instance = [Certificate new];
    instance->secCertificateRef = cert;
    return instance;
}

-(void) dealloc {
    CFRelease(secCertificateRef);
}

-(void) setAsAnchorForTrust:(SecTrustRef)trust {
    require(trust != nil);
    
    CFMutableArrayRef anchorCerts = CFArrayCreateMutable(NULL, 1, &kCFTypeArrayCallBacks);
    checkOperation(anchorCerts != NULL);
    
    CFArrayAppendValue(anchorCerts, secCertificateRef);
    OSStatus setAnchorResult = SecTrustSetAnchorCertificates(trust, anchorCerts);
    CFRelease(anchorCerts);

    checkOperationDescribe(setAnchorResult == 0,
                           ([NSString stringWithFormat:@"SecTrustSetAnchorCertificates failed with error code: %ld",
                             setAnchorResult]));
}

-(NSString *)description {
    return (__bridge_transfer NSString*)SecCertificateCopySubjectSummary(secCertificateRef);
}

@end

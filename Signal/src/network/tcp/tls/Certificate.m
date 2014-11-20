#import "Certificate.h"
#import "Util.h"

@interface Certificate ()

@property (nonatomic) SecCertificateRef secCertificateRef;

@end

@implementation Certificate

- (instancetype)initWithCertificate:(SecCertificateRef)cert {
    if (self = [super init]) {
        self.secCertificateRef = cert;
    }
    
    return self;
}

- (instancetype)initFromTrust:(SecTrustRef)trust
                      atIndex:(CFIndex)index {
    require(trust != nil);
    require(index >= 0);
    
    SecCertificateRef cert = SecTrustGetCertificateAtIndex(trust, index);
    checkOperation(cert != nil);
    CFRetain(cert);
    
    return [self initWithCertificate:cert];
}

- (instancetype)initFromResourcePath:(NSString*)resourcePath
                              ofType:(NSString*)resourceType {
    require(resourcePath != nil);
    require(resourceType != nil);
    
    NSString* certPath = [NSBundle.mainBundle pathForResource:resourcePath ofType:resourceType];
    NSData* certData = [[NSData alloc] initWithContentsOfFile:certPath];
    checkOperation(certData != nil);
    
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    checkOperation(cert != nil);
    
    return [self initWithCertificate:cert];
}

- (void)dealloc {
    CFRelease(self.secCertificateRef);
}

- (void)setAsAnchorForTrust:(SecTrustRef)trust {
    require(trust != nil);
    
    CFMutableArrayRef anchorCerts = CFArrayCreateMutable(NULL, 1, &kCFTypeArrayCallBacks);
    checkOperation(anchorCerts != NULL);
    
    CFArrayAppendValue(anchorCerts, self.secCertificateRef);
    OSStatus setAnchorResult = SecTrustSetAnchorCertificates(trust, anchorCerts);
    CFRelease(anchorCerts);

    checkOperationDescribe(setAnchorResult == 0,
                           ([NSString stringWithFormat:@"SecTrustSetAnchorCertificates failed with error code: %d",
                             (int)setAnchorResult]));
}

- (NSString*)description {
    return (__bridge_transfer NSString*)SecCertificateCopySubjectSummary(self.secCertificateRef);
}

@end

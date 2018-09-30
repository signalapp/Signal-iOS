//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, CDSSigningCertificateErrorCode) {
    // AssertionError's indicate either developer or some serious system error that should never happen.
    //
    // Do not use this for an "expected" error, e.g. something that could be induced by user input which
    // we specifically need to handle gracefull.
    CDSSigningCertificateError_AssertionError = 1,

    CDSSigningCertificateError_InvalidPEMSupplied,
    CDSSigningCertificateError_CouldNotExtractLeafCertificate,
    CDSSigningCertificateError_InvalidDistinguishedName,
    CDSSigningCertificateError_UntrustedCertificate
};

NSError *CDSSigningCertificateErrorMake(CDSSigningCertificateErrorCode code, NSString *localizedDescription);

@interface CDSSigningCertificate : NSObject

+ (nullable CDSSigningCertificate *)parseCertificateFromPem:(NSString *)certificatePem error:(NSError **)error;

- (BOOL)verifySignatureOfBody:(NSString *)body signature:(NSData *)theirSignature;

@end

NS_ASSUME_NONNULL_END

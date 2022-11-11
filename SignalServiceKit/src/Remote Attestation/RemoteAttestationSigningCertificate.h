//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, RemoteAttestationSigningCertificateErrorCode) {
    // AssertionError's indicate either developer or some serious system error that should never happen.
    //
    // Do not use this for an "expected" error, e.g. something that could be induced by user input which
    // we specifically need to handle gracefully.
    RemoteAttestationSigningCertificateError_AssertionError = 1,

    RemoteAttestationSigningCertificateError_InvalidPEMSupplied,
    RemoteAttestationSigningCertificateError_CouldNotExtractLeafCertificate,
    RemoteAttestationSigningCertificateError_InvalidDistinguishedName,
    RemoteAttestationSigningCertificateError_UntrustedCertificate
};

NSError *RemoteAttestationSigningCertificateErrorMake(RemoteAttestationSigningCertificateErrorCode code, NSString *localizedDescription);

@interface RemoteAttestationSigningCertificate : NSObject

+ (nullable RemoteAttestationSigningCertificate *)parseCertificateFromPem:(NSString *)certificatePem error:(NSError **)error;

- (BOOL)verifySignatureOfBody:(NSString *)body signature:(NSData *)theirSignature;

@end

NS_ASSUME_NONNULL_END

//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "RatchetingSession.h"
#import "AliceAxolotlParameters.h"
#import "BobAxolotlParameters.h"
#import "ChainKey.h"
#import "RootKey.h"
#import "SessionState.h"
#import <Curve25519Kit/Curve25519.h>
#import <HKDFKit/HKDFKit.h>
#import <SignalCoreKit/SCKExceptionWrapper.h>
#import <SignalCoreKit/OWSAsserts.h>

@interface DHEResult : NSObject

@property (nonatomic, readonly) RootKey *rootKey;
@property (nonatomic, readonly) NSData *chainKey;

- (instancetype)init_throws_withMasterKey:(NSData *)data NS_SWIFT_UNAVAILABLE("throws objc exceptions");

@end

@implementation DHEResult

- (instancetype)init_throws_withMasterKey:(NSData *)data
{
    // DHE Result is expected to be the result of 3 or 4 DHEs outputting 32 bytes each,
    // plus the 32 discontinuity bytes added to make V3 incompatible with V2
    OWSAssert([data length] == 32 * 4 || [data length] == 32 * 5);

    self                           = [super init];
    const char *HKDFDefaultSalt[4] = {0};
    NSData *salt                   = [NSData dataWithBytes:HKDFDefaultSalt length:sizeof(HKDFDefaultSalt)];
    NSData *info                   = [@"WhisperText" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *derivedMaterial = [HKDFKit deriveKey:data info:info salt:salt outputSize:64];
    OWSAssert(derivedMaterial.length == 64);
    _rootKey                       = [[RootKey alloc] initWithData:[derivedMaterial subdataWithRange:NSMakeRange(0, 32)]];
    _chainKey                      = [derivedMaterial subdataWithRange:NSMakeRange(32, 32)];

    return self;
}

@end


@implementation RatchetingSession

+ (void)throws_initializeSession:(SessionState *)session
                  sessionVersion:(int)sessionVersion
                 AliceParameters:(AliceAxolotlParameters *)parameters
{
    OWSAssert(session);
    OWSAssert(parameters);

    ECKeyPair *sendingRatchetKey = [Curve25519 generateKeyPair];
    OWSAssert(sendingRatchetKey);
    [self throws_initializeSession:session
                    sessionVersion:sessionVersion
                   AliceParameters:parameters
                     senderRatchet:sendingRatchetKey];
}

+ (BOOL)initializeSession:(SessionState *)session
           sessionVersion:(int)sessionVersion
            bobParameters:(BobAxolotlParameters *)bobParameters
                    error:(NSError **)outError
{
    return [SCKExceptionWrapper
        tryBlock:^{
            [self throws_initializeSession:session sessionVersion:sessionVersion BobParameters:bobParameters];
        }
           error:outError];
}

+ (void)throws_initializeSession:(SessionState *)session
                  sessionVersion:(int)sessionVersion
                   BobParameters:(BobAxolotlParameters *)parameters
{
    OWSAssert(session);
    OWSAssert(parameters);

    [session setVersion:sessionVersion];
    [session setRemoteIdentityKey:parameters.theirIdentityKey];
    [session setLocalIdentityKey:parameters.ourIdentityKeyPair.publicKey];

    DHEResult *result = [self throws_DHEKeyAgreement:parameters];
    OWSAssert(result);

    [session setSenderChain:parameters.ourRatchetKey chainKey:[[ChainKey alloc]initWithData:result.chainKey index:0]];
    [session setRootKey:result.rootKey];
}

+ (BOOL)initializeSession:(SessionState *)session
           sessionVersion:(int)sessionVersion
          aliceParameters:(AliceAxolotlParameters *)aliceParameters
                    error:(NSError **)outError
{
    return [SCKExceptionWrapper
        tryBlock:^{
            [self throws_initializeSession:session sessionVersion:sessionVersion AliceParameters:aliceParameters];
        }
           error:outError];
}

+ (void)throws_initializeSession:(SessionState *)session
                  sessionVersion:(int)sessionVersion
                 AliceParameters:(AliceAxolotlParameters *)parameters
                   senderRatchet:(ECKeyPair *)sendingRatchet
{

    OWSAssert(session);
    OWSAssert(parameters);
    OWSAssert(sendingRatchet);

    [session setVersion:sessionVersion];
    [session setRemoteIdentityKey:parameters.theirIdentityKey];
    [session setLocalIdentityKey:parameters.ourIdentityKeyPair.publicKey];

    DHEResult *result = [self throws_DHEKeyAgreement:parameters];
    OWSAssert(result);
    RKCK *sendingChain =
        [result.rootKey throws_createChainWithTheirEphemeral:parameters.theirRatchetKey ourEphemeral:sendingRatchet];
    OWSAssert(sendingChain);

    [session addReceiverChain:parameters.theirRatchetKey chainKey:[[ChainKey alloc]initWithData:result.chainKey index:0]];
    [session setSenderChain:sendingRatchet chainKey:sendingChain.chainKey];
    [session setRootKey:sendingChain.rootKey];
}

+ (DHEResult *)throws_DHEKeyAgreement:(id<AxolotlParameters>)parameters
{
    OWSAssert(parameters);

    NSMutableData *masterKey = [NSMutableData data];

    [masterKey appendData:[self discontinuityBytes]];

    if ([parameters isKindOfClass:[AliceAxolotlParameters class]]) {
        AliceAxolotlParameters *params = (AliceAxolotlParameters*)parameters;

        [masterKey appendData:[Curve25519 throws_generateSharedSecretFromPublicKey:params.theirSignedPreKey
                                                                        andKeyPair:params.ourIdentityKeyPair]];
        [masterKey appendData:[Curve25519 throws_generateSharedSecretFromPublicKey:params.theirIdentityKey
                                                                        andKeyPair:params.ourBaseKey]];
        [masterKey appendData:[Curve25519 throws_generateSharedSecretFromPublicKey:params.theirSignedPreKey
                                                                        andKeyPair:params.ourBaseKey]];
        if (params.theirOneTimePrekey) {
            [masterKey appendData:[Curve25519 throws_generateSharedSecretFromPublicKey:params.theirOneTimePrekey
                                                                            andKeyPair:params.ourBaseKey]];
        }
    } else if ([parameters isKindOfClass:[BobAxolotlParameters class]]){
        BobAxolotlParameters *params = (BobAxolotlParameters*)parameters;

        [masterKey appendData:[Curve25519 throws_generateSharedSecretFromPublicKey:params.theirIdentityKey
                                                                        andKeyPair:params.ourSignedPrekey]];
        [masterKey appendData:[Curve25519 throws_generateSharedSecretFromPublicKey:params.theirBaseKey
                                                                        andKeyPair:params.ourIdentityKeyPair]];
        [masterKey appendData:[Curve25519 throws_generateSharedSecretFromPublicKey:params.theirBaseKey
                                                                        andKeyPair:params.ourSignedPrekey]];
        if (params.ourOneTimePrekey) {
            [masterKey appendData:[Curve25519 throws_generateSharedSecretFromPublicKey:params.theirBaseKey
                                                                            andKeyPair:params.ourOneTimePrekey]];
        }
    }

    return [[DHEResult alloc] init_throws_withMasterKey:masterKey];
}

/**
 *  The discontinuity bytes enforce that the session initialization is different between protocol V2 and V3.
 *
 *  @return Returns 32-bytes of 0xFF
 */

+ (NSData*)discontinuityBytes{
    NSMutableData *discontinuity = [NSMutableData data];
    int8_t byte = 0xFF;

    for (int i = 0; i < 32; i++) {
        [discontinuity appendBytes:&byte length:sizeof(int8_t)];
    }
    return [NSData dataWithData:discontinuity];
}


@end

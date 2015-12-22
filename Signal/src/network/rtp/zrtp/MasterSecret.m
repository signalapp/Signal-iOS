#import "MasterSecret.h"
#import "ShortAuthenticationStringGenerator.h"

#define INITIATOR_SRTP_KEY_LABEL @"Initiator SRTP master key"
#define RESPONDER_SRTP_KEY_LABEL @"Responder SRTP master key"
#define INITIATOR_SRTP_SALT_LABEL @"Initiator SRTP master salt"
#define RESPONDER_SRTP_SALT_LABEL @"Responder SRTP master salt"
#define INITIATOR_MAC_KEY_LABEL @"Initiator HMAC key"
#define RESPONDER_MAC_KEY_LABEL @"Responder HMAC key"
#define INITIATOR_ZRTP_KEY_LABEL @"Initiator ZRTP key"
#define RESPONDER_ZRTP_KEY_LABEL @"Responder ZRTP key"
#define SAS_LABEL @"SAS"

#define INITIATOR_SRTP_KEY_LENGTH 16
#define RESPONDER_SRTP_KEY_LENGTH 16
#define INITIATOR_SRTP_SALT_LENGTH 14
#define RESPONDER_SRTP_SALT_LENGTH 14
#define INITIATOR_MAC_KEY_LENGTH 20
#define RESPONDER_MAC_KEY_LENGTH 20
#define INITIATOR_ZRTP_KEY_LENGTH 16
#define RESPONDER_ZRTP_KEY_LENGTH 16
#define SAS_LENGTH 4

@implementation MasterSecret

@synthesize initiatorMacKey, initiatorSrtpSalt, initiatorZrtpKey, initiatorSrtpKey, initiatorZid, responderMacKey,
    responderSrtpSalt, responderZrtpKey, responderSrtpKey, responderZid, shortAuthenticationStringData, sharedSecret,
    totalHash, counter;

+ (MasterSecret *)masterSecretFromDhResult:(NSData *)dhResult
                         andInitiatorHello:(HelloPacket *)initiatorHello
                         andResponderHello:(HelloPacket *)responderHello
                                 andCommit:(CommitPacket *)commit
                                andDhPart1:(DhPacket *)dhPart1
                                andDhPart2:(DhPacket *)dhPart2 {
    ows_require(dhResult != nil);
    ows_require(initiatorHello != nil);
    ows_require(responderHello != nil);
    ows_require(commit != nil);
    ows_require(dhPart1 != nil);
    ows_require(dhPart2 != nil);

    NSData *totalHash = [self calculateTotalHashFromResponderHello:responderHello
                                                         andCommit:commit
                                                        andDhPart1:dhPart1
                                                        andDhPart2:dhPart2];

    NSData *sharedSecret = [self calculateSharedSecretFromDhResult:dhResult
                                                      andTotalHash:totalHash
                                                   andInitiatorZid:[initiatorHello zid]
                                                   andResponderZid:[responderHello zid]];

    return [MasterSecret masterSecretFromSharedSecret:sharedSecret
                                         andTotalHash:totalHash
                                      andInitiatorZid:[initiatorHello zid]
                                      andResponderZid:[responderHello zid]];
}

+ (NSData *)calculateSharedSecretFromDhResult:(NSData *)dhResult
                                 andTotalHash:(NSData *)totalHash
                              andInitiatorZid:(Zid *)initiatorZid
                              andResponderZid:(Zid *)responderZid {
    ows_require(dhResult != nil);
    ows_require(totalHash != nil);
    ows_require(initiatorZid != nil);
    ows_require(responderZid != nil);

    NSData *counter  = [NSData dataWithBigEndianBytesOfUInt32:1];
    NSData *s1Length = [NSData dataWithBigEndianBytesOfUInt32:0];
    NSData *s2Length = [NSData dataWithBigEndianBytesOfUInt32:0];
    NSData *s3Length = [NSData dataWithBigEndianBytesOfUInt32:0];

    NSData *data = [@[

        counter,
        dhResult,
        @"ZRTP-HMAC-KDF".encodedAsUtf8,
        initiatorZid.getData,
        responderZid.getData,
        totalHash,
        s1Length,
        s2Length,
        s3Length

    ] ows_concatDatas];

    return [data hashWithSha256];
}

+ (NSData *)calculateTotalHashFromResponderHello:(HelloPacket *)responderHello
                                       andCommit:(CommitPacket *)commit
                                      andDhPart1:(DhPacket *)dhPart1
                                      andDhPart2:(DhPacket *)dhPart2 {
    ows_require(responderHello != nil);
    ows_require(commit != nil);
    ows_require(dhPart1 != nil);
    ows_require(dhPart2 != nil);

    NSData *data = [@[

        [[responderHello embeddedIntoHandshakePacket] dataUsedForAuthentication],
        [[commit embeddedIntoHandshakePacket] dataUsedForAuthentication],
        [[dhPart1 embeddedIntoHandshakePacket] dataUsedForAuthentication],
        [[dhPart2 embeddedIntoHandshakePacket] dataUsedForAuthentication]

    ] ows_concatDatas];

    return [data hashWithSha256];
}

+ (MasterSecret *)masterSecretFromSharedSecret:(NSData *)sharedSecret
                                  andTotalHash:(NSData *)totalHash
                               andInitiatorZid:(Zid *)initiatorZid
                               andResponderZid:(Zid *)responderZid {
    ows_require(sharedSecret != nil);
    ows_require(totalHash != nil);
    ows_require(initiatorZid != nil);
    ows_require(responderZid != nil);

    MasterSecret *s = [MasterSecret new];

    s->initiatorZid = initiatorZid;
    s->responderZid = responderZid;
    s->totalHash    = totalHash;
    s->sharedSecret = sharedSecret;
    s->counter      = [NSData dataWithBigEndianBytesOfUInt32:1];

    s->initiatorSrtpKey = [s deriveKeyWithLabel:INITIATOR_SRTP_KEY_LABEL andTruncatedLength:INITIATOR_SRTP_KEY_LENGTH];
    s->responderSrtpKey = [s deriveKeyWithLabel:RESPONDER_SRTP_KEY_LABEL andTruncatedLength:RESPONDER_SRTP_KEY_LENGTH];
    s->initiatorSrtpSalt =
        [s deriveKeyWithLabel:INITIATOR_SRTP_SALT_LABEL andTruncatedLength:INITIATOR_SRTP_SALT_LENGTH];
    s->responderSrtpSalt =
        [s deriveKeyWithLabel:RESPONDER_SRTP_SALT_LABEL andTruncatedLength:RESPONDER_SRTP_SALT_LENGTH];
    s->initiatorMacKey  = [s deriveKeyWithLabel:INITIATOR_MAC_KEY_LABEL andTruncatedLength:INITIATOR_MAC_KEY_LENGTH];
    s->responderMacKey  = [s deriveKeyWithLabel:RESPONDER_MAC_KEY_LABEL andTruncatedLength:RESPONDER_MAC_KEY_LENGTH];
    s->initiatorZrtpKey = [s deriveKeyWithLabel:INITIATOR_ZRTP_KEY_LABEL andTruncatedLength:INITIATOR_ZRTP_KEY_LENGTH];
    s->responderZrtpKey = [s deriveKeyWithLabel:RESPONDER_ZRTP_KEY_LABEL andTruncatedLength:RESPONDER_ZRTP_KEY_LENGTH];
    s->shortAuthenticationStringData = [s deriveKeyWithLabel:SAS_LABEL andTruncatedLength:SAS_LENGTH];

    return s;
}

- (NSData *)deriveKeyWithLabel:(NSString *)label andTruncatedLength:(uint16_t)truncatedLength {
    NSData *input = @[

        counter,
        label.encodedAsUtf8,
        [@[ @0 ] ows_toUint8Data],
        initiatorZid.getData,
        responderZid.getData,
        totalHash,
        [NSData dataWithBigEndianBytesOfUInt32:truncatedLength]

    ].ows_concatDatas;

    NSData *digest = [input hmacWithSha256WithKey:sharedSecret];

    return [digest take:truncatedLength];
}

- (NSString *)shortAuthenticationString {
    return [ShortAuthenticationStringGenerator generateFromData:shortAuthenticationStringData];
}

@end

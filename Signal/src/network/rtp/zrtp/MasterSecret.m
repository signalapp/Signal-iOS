#import "MasterSecret.h"
#import "NSData+Conversions.h"
#import "CryptoTools.h"
#import "ShortAuthenticationStringGenerator.h"
#import "Util.h"

#define INITIATOR_SRTP_KEY_LABEL  @"Initiator SRTP master key"
#define RESPONDER_SRTP_KEY_LABEL  @"Responder SRTP master key"
#define INITIATOR_SRTP_SALT_LABEL @"Initiator SRTP master salt"
#define RESPONDER_SRTP_SALT_LABEL @"Responder SRTP master salt"
#define INITIATOR_MAC_KEY_LABEL   @"Initiator HMAC key"
#define RESPONDER_MAC_KEY_LABEL   @"Responder HMAC key"
#define INITIATOR_ZRTP_KEY_LABEL  @"Initiator ZRTP key"
#define RESPONDER_ZRTP_KEY_LABEL  @"Responder ZRTP key"
#define SAS_LABEL                 @"SAS"

#define INITIATOR_SRTP_KEY_LENGTH  16
#define RESPONDER_SRTP_KEY_LENGTH  16
#define INITIATOR_SRTP_SALT_LENGTH 14
#define RESPONDER_SRTP_SALT_LENGTH 14
#define INITIATOR_MAC_KEY_LENGTH   20
#define RESPONDER_MAC_KEY_LENGTH   20
#define INITIATOR_ZRTP_KEY_LENGTH  16
#define RESPONDER_ZRTP_KEY_LENGTH  16
#define SAS_LENGTH                 4

@interface MasterSecret ()

@property (nonatomic, readwrite) NSData* totalHash;
@property (nonatomic, readwrite) NSData* counter;
@property (nonatomic, readwrite) NSData* sharedSecret;
@property (nonatomic, readwrite) NSData* shortAuthenticationStringData;

@property (nonatomic, readwrite) Zid* responderZid;
@property (nonatomic, readwrite) NSData* responderSrtpKey;
@property (nonatomic, readwrite) NSData* responderSrtpSalt;
@property (nonatomic, readwrite) NSData* responderMacKey;
@property (nonatomic, readwrite) NSData* responderZRTPKey;

@property (nonatomic, readwrite) Zid* initiatorZid;
@property (nonatomic, readwrite) NSData* initiatorSrtpKey;
@property (nonatomic, readwrite) NSData* initiatorSrtpSalt;
@property (nonatomic, readwrite) NSData* initiatorMacKey;
@property (nonatomic, readwrite) NSData* initiatorZRTPKey;

@end

@implementation MasterSecret

+(MasterSecret*) masterSecretFromDHResult:(NSData*)dhResult
                        andInitiatorHello:(HelloPacket*)initiatorHello
                        andResponderHello:(HelloPacket*)responderHello
                                andCommit:(CommitPacket*)commit
                               andDhPart1:(DHPacket*)dhPart1
                               andDhPart2:(DHPacket*)dhPart2 {
    require(dhResult != nil);
    require(initiatorHello != nil);
    require(responderHello != nil);
    require(commit != nil);
    require(dhPart1 != nil);
    require(dhPart2 != nil);
    
    NSData* totalHash = [self calculateTotalHashFromResponderHello:responderHello
                                                         andCommit:commit
                                                        andDhPart1:dhPart1
                                                        andDhPart2:dhPart2];
    
    NSData* sharedSecret = [self calculateSharedSecretFromDhResult:dhResult
                                                      andTotalHash:totalHash
                                                   andInitiatorZid:[initiatorHello zid]
                                                   andResponderZid:[responderHello zid]];
    
    return [[MasterSecret alloc] initFromSharedSecret:sharedSecret
                                         andTotalHash:totalHash
                                      andInitiatorZid:[initiatorHello zid]
                                      andResponderZid:[responderHello zid]];
    
}

+ (NSData*)calculateSharedSecretFromDhResult:(NSData*)dhResult
                                andTotalHash:(NSData*)totalHash
                             andInitiatorZid:(Zid*)initiatorZid
                             andResponderZid:(Zid*)responderZid {
    require(dhResult != nil);
    require(totalHash != nil);
    require(initiatorZid != nil);
    require(responderZid != nil);
    
    NSData* counter = [NSData dataWithBigEndianBytesOfUInt32:1];
    NSData* s1Length = [NSData dataWithBigEndianBytesOfUInt32:0];
    NSData* s2Length = [NSData dataWithBigEndianBytesOfUInt32:0];
    NSData* s3Length = [NSData dataWithBigEndianBytesOfUInt32:0];
    
    NSData* data = [@[
                    
                    counter,
                    dhResult,
                    @"ZRTP-HMAC-KDF".encodedAsUtf8,
                    initiatorZid.data,
                    responderZid.data,
                    totalHash,
                    s1Length,
                    s2Length,
                    s3Length
                    
                    ] concatDatas];
    
    return [data hashWithSha256];
}

+ (NSData*)calculateTotalHashFromResponderHello:(HelloPacket*)responderHello
                                      andCommit:(CommitPacket*)commit
                                     andDhPart1:(DHPacket*)dhPart1
                                     andDhPart2:(DHPacket*)dhPart2 {
    require(responderHello != nil);
    require(commit != nil);
    require(dhPart1 != nil);
    require(dhPart2 != nil);
    
    NSData* data = [@[
                    
                    [[responderHello embeddedIntoHandshakePacket] dataUsedForAuthentication],
                    [[commit embeddedIntoHandshakePacket] dataUsedForAuthentication],
                    [[dhPart1 embeddedIntoHandshakePacket] dataUsedForAuthentication],
                    [[dhPart2 embeddedIntoHandshakePacket] dataUsedForAuthentication]
                    
                    ] concatDatas];
    
    return [data hashWithSha256];
    
}

- (instancetype)initFromSharedSecret:(NSData*)sharedSecret
                        andTotalHash:(NSData*)totalHash
                     andInitiatorZid:(Zid*)initiatorZid
                     andResponderZid:(Zid*)responderZid {
    if (self = [super init]) {
        require(sharedSecret != nil);
        require(totalHash != nil);
        require(initiatorZid != nil);
        require(responderZid != nil);
        
        self.initiatorZid                  = initiatorZid;
        self.responderZid                  = responderZid;
        self.totalHash                     = totalHash;
        self.sharedSecret                  = sharedSecret;
        self.counter                       = [NSData dataWithBigEndianBytesOfUInt32:1];
        
        self.initiatorSrtpKey              = [self deriveKeyWithLabel:INITIATOR_SRTP_KEY_LABEL
                                                   andTruncatedLength:INITIATOR_SRTP_KEY_LENGTH];
        self.responderSrtpKey              = [self deriveKeyWithLabel:RESPONDER_SRTP_KEY_LABEL
                                                   andTruncatedLength:RESPONDER_SRTP_KEY_LENGTH];
        self.initiatorSrtpSalt             = [self deriveKeyWithLabel:INITIATOR_SRTP_SALT_LABEL
                                                   andTruncatedLength:INITIATOR_SRTP_SALT_LENGTH];
        self.responderSrtpSalt             = [self deriveKeyWithLabel:RESPONDER_SRTP_SALT_LABEL
                                                   andTruncatedLength:RESPONDER_SRTP_SALT_LENGTH];
        self.initiatorMacKey               = [self deriveKeyWithLabel:INITIATOR_MAC_KEY_LABEL
                                                   andTruncatedLength:INITIATOR_MAC_KEY_LENGTH];
        self.responderMacKey               = [self deriveKeyWithLabel:RESPONDER_MAC_KEY_LABEL
                                                   andTruncatedLength:RESPONDER_MAC_KEY_LENGTH];
        self.initiatorZRTPKey              = [self deriveKeyWithLabel:INITIATOR_ZRTP_KEY_LABEL
                                                   andTruncatedLength:INITIATOR_ZRTP_KEY_LENGTH];
        self.responderZRTPKey              = [self deriveKeyWithLabel:RESPONDER_ZRTP_KEY_LABEL
                                                   andTruncatedLength:RESPONDER_ZRTP_KEY_LENGTH];
        self.shortAuthenticationStringData = [self deriveKeyWithLabel:SAS_LABEL
                                                   andTruncatedLength:SAS_LENGTH];
    }
    
    return self;
}

- (NSData*)deriveKeyWithLabel:(NSString*)label andTruncatedLength:(uint16_t)truncatedLength {
    NSData* input = @[
                     
                     self.counter,
                     label.encodedAsUtf8,
                     [@[@0] toUint8Data],
                     self.initiatorZid.data,
                     self.responderZid.data,
                     self.totalHash,
                     [NSData dataWithBigEndianBytesOfUInt32:truncatedLength]
                     
                     ].concatDatas;
    
    NSData* digest = [input hmacWithSha256WithKey:self.sharedSecret];
    
    return [digest take:truncatedLength];
}

- (NSString*)shortAuthenticationString {
    return [ShortAuthenticationStringGenerator generateFromData:self.shortAuthenticationStringData];
}

@end

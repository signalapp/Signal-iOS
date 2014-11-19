#import "CommitPacket.h"
#import "Util.h"
#import "CryptoTools.h"
#import "NSData+CryptoTools.h"

#define         ZID_LENGTH      12
#define   HASH_SPEC_LENGTH      4
#define CIPHER_SPEC_LENGTH      4
#define   AUTH_SPEC_LENGTH      4
#define  AGREE_SPEC_LENGTH      4
#define    SAS_SPEC_LENGTH      4
#define      COMMIT_LENGTH      32

#define   HASH_SPEC_OFFSET      HASH_CHAIN_ITEM_LENGTH + ZID_LENGTH
#define CIPHER_SPEC_OFFSET      HASH_SPEC_OFFSET    +    HASH_SPEC_LENGTH
#define   AUTH_SPEC_OFFSET      CIPHER_SPEC_OFFSET  +  CIPHER_SPEC_LENGTH
#define  AGREE_SPEC_OFFSET      AUTH_SPEC_OFFSET    +    AUTH_SPEC_LENGTH
#define    SAS_SPEC_OFFSET      AGREE_SPEC_OFFSET   +   AGREE_SPEC_LENGTH
#define      COMMIT_OFFSET        SAS_SPEC_OFFSET   +     SAS_SPEC_LENGTH

@interface CommitPacket ()

@property (strong, readwrite, nonatomic) NSData* h2;
@property (strong, readwrite, nonatomic) NSData* hashSpecId;
@property (strong, readwrite, nonatomic) NSData* cipherSpecId;
@property (strong, readwrite, nonatomic) NSData* authSpecId;
@property (strong, readwrite, nonatomic) NSData* agreementSpecId;
@property (strong, readwrite, nonatomic) NSData* sasSpecId;
@property (strong, readwrite, nonatomic) Zid* zid;
@property (strong, readwrite, nonatomic) NSData* dhPart2HelloCommitment;

@property (strong, readwrite, nonatomic, getter=embeddedIntoHandshakePacket) HandshakePacket* embedding;

@end

@implementation CommitPacket

+ (instancetype)defaultPacketWithKeyAgreementProtocol:(id<KeyAgreementProtocol>)keyAgreementProtocol
                                         andHashChain:(HashChain*)hashChain
                                               andZid:(Zid*)zid
                                 andCommitmentToHello:(HelloPacket*)hello
                                           andDHPart2:(DHPacket*)dhPart2 {
    
    require(keyAgreementProtocol != nil);
    require(hashChain != nil);
    require(zid != nil);
    require(hello != nil);
    require(dhPart2 != nil);
    
    NSData* dhPart2Data = [[dhPart2 embeddedIntoHandshakePacket] dataUsedForAuthentication];
    NSData* helloData = [[hello embeddedIntoHandshakePacket] dataUsedForAuthentication];
    return [[self alloc] initWithHashChainH2:hashChain.h2
                                      andZid:zid
                               andHashSpecId:COMMIT_DEFAULT_HASH_SPEC_ID
                             andCipherSpecId:COMMIT_DEFAULT_CIPHER_SPEC_ID
                               andAuthSpecId:COMMIT_DEFAULT_AUTH_SPEC_ID
                              andAgreeSpecId:keyAgreementProtocol.getId
                                andSasSpecId:COMMIT_DEFAULT_SAS_SPEC_ID
                   andDHPart2HelloCommitment:[[@[dhPart2Data, helloData] concatDatas] hashWithSHA256]
                                  andHMACKey:hashChain.h1];
}

- (instancetype)initWithHashChainH2:(NSData*)h2
                             andZid:(Zid*)zid
                      andHashSpecId:(NSData*)hashSpecId
                    andCipherSpecId:(NSData*)cipherSpecId
                      andAuthSpecId:(NSData*)authSpecId
                     andAgreeSpecId:(NSData*)agreeSpecId
                       andSasSpecId:(NSData*)sasSpecId
          andDHPart2HelloCommitment:(NSData*)dhPart2HelloCommitment
                         andHMACKey:(NSData*)hmacKey {
    if (self = [super init]) {
        require(h2 != nil);
        require(zid != nil);
        require(hashSpecId != nil);
        require(cipherSpecId != nil);
        require(authSpecId != nil);
        require(agreeSpecId != nil);
        require(sasSpecId != nil);
        require(dhPart2HelloCommitment != nil);
        require(hmacKey != nil);
        
        require(h2.length == HASH_CHAIN_ITEM_LENGTH);
        require(hashSpecId.length == HASH_SPEC_LENGTH);
        require(cipherSpecId.length == CIPHER_SPEC_LENGTH);
        require(authSpecId.length == AUTH_SPEC_LENGTH);
        require(agreeSpecId.length == AGREE_SPEC_LENGTH);
        require(sasSpecId.length == SAS_SPEC_LENGTH);
        
        self.h2                     = h2;
        self.zid                    = zid;
        self.hashSpecId             = hashSpecId;
        self.cipherSpecId           = cipherSpecId;
        self.authSpecId             = authSpecId;
        self.agreementSpecId        = agreeSpecId;
        self.sasSpecId              = sasSpecId;
        self.dhPart2HelloCommitment = dhPart2HelloCommitment;
        
        self.embedding              = [self embedInHandshakePacketAuthenticatedWith:hmacKey];
    }
    
    return self;
}

- (instancetype)initFromHandshakePacket:(HandshakePacket*)handshakePacket {
    if (self = [super init]) {
        require(handshakePacket != nil);
        checkOperation([[handshakePacket typeId] isEqualToData:HANDSHAKE_TYPE_COMMIT]);
        NSData* payload = [handshakePacket payload];
        checkOperation(payload.length == COMMIT_OFFSET + COMMIT_LENGTH + HANDSHAKE_TRUNCATED_HMAC_LENGTH);
        
        self.h2                     = [self getH2FromPayload:payload];
        self.zid                    = [self getZidFromPayload:payload];
        self.hashSpecId             = [self getHashSpecIdFromPayload:payload];
        self.cipherSpecId           = [self getCipherSpecIdFromPayload:payload];
        self.authSpecId             = [self getAuthSpecIdFromPayload:payload];
        self.agreementSpecId        = [self getAgreeSpecIdFromPayload:payload];
        self.sasSpecId              = [self getSasSpecIdFromPayload:payload];
        self.dhPart2HelloCommitment = [self getCommitmentFromPayload:payload];
        
        self.embedding              = handshakePacket;
    }
    
    return self;
}

- (HandshakePacket*)embedInHandshakePacketAuthenticatedWith:(NSData*)hmacKey {
    
    require(hmacKey != nil);
    requireState(self.h2.length              == HASH_CHAIN_ITEM_LENGTH);
    requireState(self.hashSpecId.length      == HASH_SPEC_LENGTH);
    requireState(self.cipherSpecId.length    == CIPHER_SPEC_LENGTH);
    requireState(self.authSpecId.length      == AUTH_SPEC_LENGTH);
    requireState(self.agreementSpecId.length == AGREE_SPEC_LENGTH);
    requireState(self.sasSpecId.length       == SAS_SPEC_LENGTH);
    
    NSData* payload = [@[
                       self.h2,
                       self.zid.data,
                       self.hashSpecId,
                       self.cipherSpecId,
                       self.authSpecId,
                       self.agreementSpecId,
                       self.sasSpecId,
                       self.dhPart2HelloCommitment
                       ] concatDatas];
    
    return [[[HandshakePacket alloc] initWithTypeId:HANDSHAKE_TYPE_COMMIT andPayload:payload] withHMACAppended:hmacKey];
}

- (void)verifyCommitmentAgainstHello:(HelloPacket*)hello
                          andDHPart2:(DHPacket*)dhPart2 {
    require(hello != nil);
    require(dhPart2 != nil);
    
    NSData* expected = [[@[
                         [[dhPart2 embeddedIntoHandshakePacket] dataUsedForAuthentication],
                         [[hello embeddedIntoHandshakePacket] dataUsedForAuthentication]]
                         concatDatas] hashWithSHA256];
    checkOperation([self.dhPart2HelloCommitment isEqualToData_TimingSafe:expected]);
}

- (void)verifyMacWithHashChainH1:(NSData*)hashChainH1 {
    checkOperation([[hashChainH1 hashWithSHA256] isEqualToData_TimingSafe:self.h2]);
    [self.embedding withHMACVerifiedAndRemoved:hashChainH1];
}

- (NSData*)getH2FromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(0, HASH_CHAIN_ITEM_LENGTH)];
}

- (Zid*)getZidFromPayload:(NSData*)payload {
    return [[Zid alloc] initWithData:[payload subdataWithRange:NSMakeRange(HASH_CHAIN_ITEM_LENGTH, ZID_LENGTH)]];
}

- (NSData*)getHashSpecIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(HASH_SPEC_OFFSET, HASH_SPEC_LENGTH)];
}

- (NSData*)getCipherSpecIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(CIPHER_SPEC_OFFSET, CIPHER_SPEC_LENGTH)];
}

- (NSData*)getAuthSpecIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(AUTH_SPEC_OFFSET, AUTH_SPEC_LENGTH)];
}

- (NSData*)getAgreeSpecIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(AGREE_SPEC_OFFSET, AGREE_SPEC_LENGTH)];
}

- (NSData*)getSasSpecIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(SAS_SPEC_OFFSET, SAS_SPEC_LENGTH)];
}

- (NSData*)getCommitmentFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(COMMIT_OFFSET, COMMIT_LENGTH)];
}

@end

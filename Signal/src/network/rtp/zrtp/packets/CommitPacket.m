#import "CommitPacket.h"

@implementation CommitPacket

@synthesize agreementSpecId, authSpecId, cipherSpecId, dhPart2HelloCommitment, h2, hashSpecId, sasSpecId, zid;


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


+(CommitPacket*) commitPacketWithDefaultSpecsAndKeyAgreementProtocol:(id<KeyAgreementProtocol>)keyAgreementProtocol
                                                        andHashChain:(HashChain*)hashChain
                                                              andZid:(Zid*)zid
                                                andCommitmentToHello:(HelloPacket*)hello
                                                          andDhPart2:(DhPacket*)dhPart2 {
    
    ows_require(keyAgreementProtocol != nil);
    ows_require(hashChain != nil);
    ows_require(zid != nil);
    ows_require(hello != nil);
    ows_require(dhPart2 != nil);
    
    NSData* dhPart2Data = [[dhPart2 embeddedIntoHandshakePacket] dataUsedForAuthentication];
    NSData* helloData = [[hello embeddedIntoHandshakePacket] dataUsedForAuthentication];
    return [CommitPacket commitPacketWithHashChainH2:hashChain.h2
                                              andZid:zid
                                       andHashSpecId:COMMIT_DEFAULT_HASH_SPEC_ID
                                     andCipherSpecId:COMMIT_DEFAULT_CIPHER_SPEC_ID
                                       andAuthSpecId:COMMIT_DEFAULT_AUTH_SPEC_ID
                                      andAgreeSpecId:keyAgreementProtocol.getId
                                        andSasSpecId:COMMIT_DEFAULT_SAS_SPEC_ID
                           andDhPart2HelloCommitment:@[dhPart2Data, helloData].ows_concatDatas.hashWithSha256
                                          andHmacKey:hashChain.h1];
}

+(CommitPacket*) commitPacketWithHashChainH2:(NSData*)h2
                                      andZid:(Zid*)zid
                               andHashSpecId:(NSData*)hashSpecId
                             andCipherSpecId:(NSData*)cipherSpecId
                               andAuthSpecId:(NSData*)authSpecId
                              andAgreeSpecId:(NSData*)agreeSpecId
                                andSasSpecId:(NSData*)sasSpecId
                   andDhPart2HelloCommitment:(NSData*)dhPart2HelloCommitment
                                  andHmacKey:(NSData*)hmacKey {
    
    ows_require(h2 != nil);
    ows_require(zid != nil);
    ows_require(hashSpecId != nil);
    ows_require(cipherSpecId != nil);
    ows_require(authSpecId != nil);
    ows_require(agreeSpecId != nil);
    ows_require(sasSpecId != nil);
    ows_require(dhPart2HelloCommitment != nil);
    ows_require(hmacKey != nil);
    
    ows_require(h2.length == HASH_CHAIN_ITEM_LENGTH);
    ows_require(hashSpecId.length == HASH_SPEC_LENGTH);
    ows_require(cipherSpecId.length == CIPHER_SPEC_LENGTH);
    ows_require(authSpecId.length == AUTH_SPEC_LENGTH);
    ows_require(agreeSpecId.length == AGREE_SPEC_LENGTH);
    ows_require(sasSpecId.length == SAS_SPEC_LENGTH);
    
    CommitPacket* p = [CommitPacket new];
    
    p->h2 = h2;
    p->zid = zid;
    p->hashSpecId = hashSpecId;
    p->cipherSpecId = cipherSpecId;
    p->authSpecId = authSpecId;
    p->agreementSpecId = agreeSpecId;
    p->sasSpecId = sasSpecId;
    p->dhPart2HelloCommitment = dhPart2HelloCommitment;
    
    p->embedding = [p embedInHandshakePacketAuthenticatedWith:hmacKey];
    
    return p;
}
-(HandshakePacket*) embedInHandshakePacketAuthenticatedWith:(NSData*)hmacKey {
    
    ows_require(hmacKey != nil);
    requireState(h2.length == HASH_CHAIN_ITEM_LENGTH);
    requireState(hashSpecId.length == HASH_SPEC_LENGTH);
    requireState(cipherSpecId.length == CIPHER_SPEC_LENGTH);
    requireState(authSpecId.length == AUTH_SPEC_LENGTH);
    requireState(agreementSpecId.length == AGREE_SPEC_LENGTH);
    requireState(sasSpecId.length == SAS_SPEC_LENGTH);
    
    NSData* payload = @[
                       h2,
                       zid.getData,
                       hashSpecId,
                       cipherSpecId,
                       authSpecId,
                       agreementSpecId,
                       sasSpecId,
                       dhPart2HelloCommitment
                       ].ows_concatDatas;
    
    return [[HandshakePacket handshakePacketWithTypeId:HANDSHAKE_TYPE_COMMIT andPayload:payload] withHmacAppended:hmacKey];
}
-(void) verifyCommitmentAgainstHello:(HelloPacket*)hello andDhPart2:(DhPacket*)dhPart2 {
    ows_require(hello != nil);
    ows_require(dhPart2 != nil);
    
    NSData* expected = [[@[
                         [[dhPart2 embeddedIntoHandshakePacket] dataUsedForAuthentication],
                         [[hello embeddedIntoHandshakePacket] dataUsedForAuthentication]]
                         ows_concatDatas] hashWithSha256];
    checkOperation([dhPart2HelloCommitment isEqualToData_TimingSafe:expected]);
}
-(void) verifyMacWithHashChainH1:(NSData*)hashChainH1 {
    checkOperation([[hashChainH1 hashWithSha256] isEqualToData_TimingSafe:h2]);
    [embedding withHmacVerifiedAndRemoved:hashChainH1];
}

+(NSData*) getH2FromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(0, HASH_CHAIN_ITEM_LENGTH)];
}
+(Zid*) getZidFromPayload:(NSData*)payload {
    return [Zid zidWithData:[payload subdataWithRange:NSMakeRange(HASH_CHAIN_ITEM_LENGTH, ZID_LENGTH)]];
}
+(NSData*) getHashSpecIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(HASH_SPEC_OFFSET, HASH_SPEC_LENGTH)];
}
+(NSData*) getCipherSpecIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(CIPHER_SPEC_OFFSET, CIPHER_SPEC_LENGTH)];
}
+(NSData*) getAuthSpecIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(AUTH_SPEC_OFFSET, AUTH_SPEC_LENGTH)];
}
+(NSData*) getAgreeSpecIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(AGREE_SPEC_OFFSET, AGREE_SPEC_LENGTH)];
}
+(NSData*) getSasSpecIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(SAS_SPEC_OFFSET, SAS_SPEC_LENGTH)];
}
+(NSData*) getCommitmentFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(COMMIT_OFFSET, COMMIT_LENGTH)];
}
+(CommitPacket*) commitPacketParsedFromHandshakePacket:(HandshakePacket*)handshakePacket {
    ows_require(handshakePacket != nil);
    checkOperation([[handshakePacket typeId] isEqualToData:HANDSHAKE_TYPE_COMMIT]);
    NSData* payload = [handshakePacket payload];
    checkOperation(payload.length == COMMIT_OFFSET + COMMIT_LENGTH + HANDSHAKE_TRUNCATED_HMAC_LENGTH);
    
    CommitPacket* p = [CommitPacket new];
    
    p->h2 = [self getH2FromPayload:payload];
    p->zid = [self getZidFromPayload:payload];
    p->hashSpecId = [self getHashSpecIdFromPayload:payload];
    p->cipherSpecId = [self getCipherSpecIdFromPayload:payload];
    p->authSpecId = [self getAuthSpecIdFromPayload:payload];
    p->agreementSpecId = [self getAgreeSpecIdFromPayload:payload];
    p->sasSpecId = [self getSasSpecIdFromPayload:payload];
    p->dhPart2HelloCommitment = [self getCommitmentFromPayload:payload];
    p->embedding = handshakePacket;
    
    return p;
}

-(HandshakePacket*) embeddedIntoHandshakePacket {
    return embedding;
}

@end

#import "HelloPacket.h"
#import "Environment.h"

@implementation HelloPacket

@synthesize zid, agreeIds, authIds, cipherIds, clientId, flags0SMP, flagsUnusedHigh4, flagsUnusedLow4, hashChainH3, hashIds, sasIds, versionId;

#define MAX_SPEC_IDS 7
#define CLIENT_ID_LENGTH 16
#define VERSION_ID_LENGTH 4
#define ZID_LENGTH 12
#define FLAGS_LENGTH 4
#define SPEC_ID_LENGTH 4

#define VERSION_ID_OFFSET 0
#define CLIENT_ID_OFFSET (VERSION_ID_OFFSET + VERSION_ID_LENGTH)
#define HASH_CHAIN_H3_OFFSET (CLIENT_ID_LENGTH + CLIENT_ID_OFFSET)
#define ZID_OFFSET (HASH_CHAIN_H3_OFFSET + HASH_CHAIN_ITEM_LENGTH)
#define FLAGS_OFFSET (ZID_OFFSET + ZID_LENGTH)
#define SPEC_IDS_OFFSET (FLAGS_OFFSET + FLAGS_LENGTH)

#define UNUSED_HIGH_AND_0SMP_FLAG_INDEX 0
#define HASH_ID_AND_UNUSED_LOW_FLAG_INDEX 1
#define AUTH_ID_AND_CIPHER_ID_FLAG_INDEX 2
#define SAS_ID_AND_AGREE_ID_FLAG_INDEX 3

#define FLAGS_0SMP_MASK 0xF
#define FLAGS_UNUSED_LOW_MASK 0xF
#define FLAGS_UNUSED_HIGH_MASK 0xF

#define HASH_IDS_INDEX 0
#define CIPHER_IDS_INDEX 1
#define AUTH_IDS_INDEX 2
#define AGREE_IDS_INDEX 3
#define SAS_IDS_INDEX 4

+(NSArray*) getAgreeIdsFromKeyAgreementProtocols:(NSArray*)keyAgreementProtocols {
    NSMutableArray* agreeSpecIds = [NSMutableArray array];
    bool hasDH3k = false;
    
    for (id<KeyAgreementProtocol> e in keyAgreementProtocols) {
        if ([e.getId isEqualToData:COMMIT_DEFAULT_AGREE_SPEC_ID]) {
            hasDH3k = true;
        } else {
            [agreeSpecIds addObject:e.getId];
        }
    }
    
    ows_require(hasDH3k);
    return agreeSpecIds;
}
+(HelloPacket*) helloPacketWithDefaultsAndHashChain:(HashChain*)hashChain
                                             andZid:(Zid*)zid
                           andKeyAgreementProtocols:(NSArray*)keyAgreementProtocols {
    
    ows_require(hashChain != nil);
    ows_require(zid != nil);
    ows_require(keyAgreementProtocols != nil);
    
    return [HelloPacket helloPacketWithVersion:Environment.getCurrent.zrtpVersionId
                                   andClientId:Environment.getCurrent.zrtpClientId
                                andHashChainH3:[hashChain h3]
                                        andZid:zid
                                  andFlags0SMP:0
                            andFlagsUnusedLow4:0
                           andFlagsUnusedHigh4:0
                                andHashSpecIds:@[]
                              andCipherSpecIds:@[]
                                andAuthSpecIds:@[]
                               andAgreeSpecIds:[self getAgreeIdsFromKeyAgreementProtocols:keyAgreementProtocols]
                                 andSasSpecIds:@[]
                      authenticatedWithHmacKey:[hashChain h2]];
}

+(HelloPacket*) helloPacketWithVersion:(NSData*)versionId
                           andClientId:(NSData*)clientId
                        andHashChainH3:(NSData*)hashChainH3
                                andZid:(Zid*)zid
                          andFlags0SMP:(uint8_t)flags0SMP
                    andFlagsUnusedLow4:(uint8_t)flagsUnusedLow4
                   andFlagsUnusedHigh4:(uint8_t)flagsUnusedHigh4
                        andHashSpecIds:(NSArray*)hashIds
                      andCipherSpecIds:(NSArray*)cipherIds
                        andAuthSpecIds:(NSArray*)authIds
                       andAgreeSpecIds:(NSArray*)agreeIds
                         andSasSpecIds:(NSArray*)sasIds
              authenticatedWithHmacKey:(NSData*)hmacKey {
    
    ows_require(versionId != nil);
    ows_require(clientId != nil);
    ows_require(hashChainH3 != nil);
    ows_require(hashIds != nil);
    ows_require(cipherIds != nil);
    ows_require(authIds != nil);
    ows_require(agreeIds != nil);
    ows_require(sasIds != nil);
    ows_require((flags0SMP & ~FLAGS_0SMP_MASK) == 0);
    ows_require((flagsUnusedLow4 & ~FLAGS_UNUSED_LOW_MASK) == 0);
    ows_require((flagsUnusedHigh4 & ~FLAGS_UNUSED_HIGH_MASK) == 0);
    
    ows_require(versionId.length == VERSION_ID_LENGTH);
    ows_require(clientId.length == CLIENT_ID_LENGTH);
    ows_require(hashChainH3.length == HASH_CHAIN_ITEM_LENGTH);
    ows_require(hashIds.count <= MAX_SPEC_IDS);
    ows_require(cipherIds.count <= MAX_SPEC_IDS);
    ows_require(authIds.count <= MAX_SPEC_IDS);
    ows_require(agreeIds.count <= MAX_SPEC_IDS);
    ows_require(sasIds.count <= MAX_SPEC_IDS);
    
    HelloPacket* p = [HelloPacket new];
    p->flagsUnusedLow4 = flagsUnusedLow4;
    p->flagsUnusedHigh4 = flagsUnusedHigh4;
    p->flags0SMP = flags0SMP;
    p->agreeIds = agreeIds;
    p->authIds = authIds;
    p->cipherIds = cipherIds;
    p->clientId = clientId;
    p->hashChainH3 = hashChainH3;
    p->hashIds = hashIds;
    p->sasIds = sasIds;
    p->versionId = versionId;
    p->zid = zid;
    
    HandshakePacket* unauthenticatedEmbedding = [HandshakePacket handshakePacketWithTypeId:HANDSHAKE_TYPE_HELLO andPayload:[p generatePayload]];
    p->embedding = [unauthenticatedEmbedding withHmacAppended:hmacKey];
    return p;
}
-(NSData*) generateFlags {
    NSMutableData* flags = [NSMutableData dataWithLength:FLAGS_LENGTH];
    
    [flags setUint8At:UNUSED_HIGH_AND_0SMP_FLAG_INDEX
                   to:[NumberUtil uint8FromLowUInt4:flagsUnusedHigh4
                                       andHighUInt4:flags0SMP]];
    
    [flags setUint8At:UNUSED_HIGH_AND_0SMP_FLAG_INDEX
                   to:[NumberUtil uint8FromLowUInt4:(uint8_t)hashIds.count
                                       andHighUInt4:flagsUnusedLow4]];
    
    [flags setUint8At:AUTH_ID_AND_CIPHER_ID_FLAG_INDEX
                   to:[NumberUtil uint8FromLowUInt4:(uint8_t)authIds.count
                                       andHighUInt4:(uint8_t)cipherIds.count]];
    
    [flags setUint8At:SAS_ID_AND_AGREE_ID_FLAG_INDEX
                   to:[NumberUtil uint8FromLowUInt4:(uint8_t)sasIds.count
                                       andHighUInt4:(uint8_t)agreeIds.count]];
    
    return flags;
}
-(NSData*) generatePayload {
    return [@[
            
            versionId,
            clientId,
            hashChainH3,
            zid.getData,
            [self generateFlags],
            [[@[hashIds, cipherIds, authIds, agreeIds, sasIds] ows_concatArrays] ows_concatDatas]
            
            ] ows_concatDatas];
}

-(void) verifyMacWithHashChainH2:(NSData*)hashChainH2 {
    checkOperationDescribe([[hashChainH2 hashWithSha256] isEqualToData_TimingSafe:hashChainH3], @"Invalid preimage");
    [embedding withHmacVerifiedAndRemoved:hashChainH2];
}
+(NSData*) getVersionIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(VERSION_ID_OFFSET, VERSION_ID_LENGTH)];
}
+(NSData*) getClientIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(CLIENT_ID_OFFSET, CLIENT_ID_LENGTH)];
}
+(NSData*) getHashChainH3FromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(HASH_CHAIN_H3_OFFSET, HASH_CHAIN_ITEM_LENGTH)];
}
+(Zid*) getZidFromPayload:(NSData*)payload {
    return [Zid zidWithData:[payload subdataWithRange:NSMakeRange(ZID_OFFSET, ZID_LENGTH)]];
}
+(NSArray*) getSpecIdsFromPayload:(NSData*)payload counts:(NSArray*)counts {
    checkOperation(payload.length >= SPEC_IDS_OFFSET + SPEC_ID_LENGTH*[counts sumNSUInteger]);
    
    NSMutableArray* result = [NSMutableArray array];
    NSUInteger offset = SPEC_IDS_OFFSET;
    for (NSNumber* count in counts) {
        NSMutableArray* subResult = [NSMutableArray array];
        for (NSUInteger i = 0; i < [count unsignedIntegerValue]; i++) {
            [subResult addObject:[payload subdataWithRange:NSMakeRange(offset, SPEC_ID_LENGTH)]];
            offset += SPEC_ID_LENGTH;
        }
        [result addObject:subResult];
    }
    return result;
}
-(void) setFlagsAndSpecIdsFromPayload:(NSData*)payload {
    NSData* flags = [payload subdataWithRange:NSMakeRange(FLAGS_OFFSET, FLAGS_LENGTH)];

    flags0SMP = [flags highUint4AtByteOffset:UNUSED_HIGH_AND_0SMP_FLAG_INDEX];
    flagsUnusedHigh4 = [flags lowUint4AtByteOffset:UNUSED_HIGH_AND_0SMP_FLAG_INDEX];
    flagsUnusedLow4 = [flags highUint4AtByteOffset:HASH_ID_AND_UNUSED_LOW_FLAG_INDEX];

    uint8_t hashIdsCount = [flags lowUint4AtByteOffset:HASH_ID_AND_UNUSED_LOW_FLAG_INDEX];
    uint8_t cipherIdsCount = [flags highUint4AtByteOffset:AUTH_ID_AND_CIPHER_ID_FLAG_INDEX];
    uint8_t authIdsCount = [flags lowUint4AtByteOffset:AUTH_ID_AND_CIPHER_ID_FLAG_INDEX];
    uint8_t agreeIdsCount = [flags highUint4AtByteOffset:SAS_ID_AND_AGREE_ID_FLAG_INDEX];
    uint8_t sasIdsCount = [flags lowUint4AtByteOffset:SAS_ID_AND_AGREE_ID_FLAG_INDEX];
    NSArray* counts = @[@(hashIdsCount),
                        @(cipherIdsCount),
                        @(authIdsCount),
                        @(agreeIdsCount),
                        @(sasIdsCount)];
    
    NSArray* specIds = [HelloPacket getSpecIdsFromPayload:payload counts:counts];
    hashIds = specIds[HASH_IDS_INDEX];
    cipherIds = specIds[CIPHER_IDS_INDEX];
    authIds = specIds[AUTH_IDS_INDEX];
    agreeIds = specIds[AGREE_IDS_INDEX];
    sasIds = specIds[SAS_IDS_INDEX];
}
+(HelloPacket*) helloPacketParsedFromHandshakePacket:(HandshakePacket*)handshakePacket {
    ows_require(handshakePacket != nil);
    checkOperationDescribe([[handshakePacket typeId] isEqualToData:HANDSHAKE_TYPE_HELLO], @"Not a hello packet");
    
    NSData* payload = [handshakePacket payload];
    checkOperation(payload.length >= SPEC_IDS_OFFSET);
    
    HelloPacket* p = [HelloPacket new];
    
    p->versionId = [self getVersionIdFromPayload:payload];
    p->clientId = [self getClientIdFromPayload:payload];
    p->hashChainH3 = [self getHashChainH3FromPayload:payload];
    p->zid = [self getZidFromPayload:payload];
    [p setFlagsAndSpecIdsFromPayload:payload];
    
    p->embedding = handshakePacket;
    
    return p;
}

-(HandshakePacket*) embeddedIntoHandshakePacket {
    return embedding;
}
-(NSArray*) agreeIdsIncludingImplied {
    NSMutableArray* a = agreeIds.mutableCopy;
    [a addObject:COMMIT_DEFAULT_AGREE_SPEC_ID];
    return a;
}

@end

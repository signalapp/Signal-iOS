#import "HelloPacket.h"
#import "Util.h"
#import "DH3KKeyAgreementProtocol.h"
#import "NSArray+FunctionalUtil.h"
#import "Environment.h"
#import "NSData+CryptoTools.h"

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

@interface HelloPacket ()

@property (strong, readwrite, nonatomic) NSData* versionId;
@property (strong, readwrite, nonatomic) NSData* clientId;
@property (strong, readwrite, nonatomic) NSData* hashChainH3;
@property (strong, readwrite, nonatomic) Zid* zid;
@property (readwrite, nonatomic) uint8_t flags0SMP;
@property (readwrite, nonatomic) uint8_t flagsUnusedLow4;
@property (readwrite, nonatomic) uint8_t flagsUnusedHigh4;
@property (strong, readwrite, nonatomic) NSArray* hashIds;
@property (strong, readwrite, nonatomic) NSArray* cipherIds;
@property (strong, readwrite, nonatomic) NSArray* authIds;
@property (strong, readwrite, nonatomic) NSArray* agreeIds;
@property (strong, readwrite, nonatomic) NSArray* sasIds;

@property (strong, readwrite, nonatomic, getter=embeddedIntoHandshakePacket) HandshakePacket* embedding;

@end

@implementation HelloPacket

+ (NSArray*)getAgreeIdsFromKeyAgreementProtocols:(NSArray*)keyAgreementProtocols {
    NSMutableArray* agreeSpecIds = [[NSMutableArray alloc] init];
    bool hasDH3k = false;
    
    for (id<KeyAgreementProtocol> e in keyAgreementProtocols) {
        if ([e.getId isEqualToData:COMMIT_DEFAULT_AGREE_SPEC_ID]) {
            hasDH3k = true;
        } else {
            [agreeSpecIds addObject:e.getId];
        }
    }
    
    require(hasDH3k);
    return agreeSpecIds;
}

+ (instancetype)defaultPacketWithHashChain:(HashChain*)hashChain
                                    andZid:(Zid*)zid
                  andKeyAgreementProtocols:(NSArray*)keyAgreementProtocols {
    
    require(hashChain != nil);
    require(zid != nil);
    require(keyAgreementProtocols != nil);
    
    return [[self alloc] initWithVersion:Environment.getCurrent.zrtpVersionId
                             andClientId:Environment.getCurrent.zrtpClientId
                          andHashChainH3:hashChain.h3
                                  andZid:zid
                            andFlags0SMP:0
                      andFlagsUnusedLow4:0
                     andFlagsUnusedHigh4:0
                          andHashSpecIds:@[]
                        andCipherSpecIds:@[]
                          andAuthSpecIds:@[]
                         andAgreeSpecIds:[self getAgreeIdsFromKeyAgreementProtocols:keyAgreementProtocols]
                           andSasSpecIds:@[]
                authenticatedWithHMACKey:hashChain.h2];
}

- (instancetype)initWithVersion:(NSData*)versionId
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
       authenticatedWithHMACKey:(NSData*)hmacKey {
    
    if (self = [super init]) {
        require(versionId != nil);
        require(clientId != nil);
        require(hashChainH3 != nil);
        require(hashIds != nil);
        require(cipherIds != nil);
        require(authIds != nil);
        require(agreeIds != nil);
        require(sasIds != nil);
        require((flags0SMP & ~FLAGS_0SMP_MASK) == 0);
        require((flagsUnusedLow4 & ~FLAGS_UNUSED_LOW_MASK) == 0);
        require((flagsUnusedHigh4 & ~FLAGS_UNUSED_HIGH_MASK) == 0);
        
        require(versionId.length == VERSION_ID_LENGTH);
        require(clientId.length == CLIENT_ID_LENGTH);
        require(hashChainH3.length == HASH_CHAIN_ITEM_LENGTH);
        require(hashIds.count <= MAX_SPEC_IDS);
        require(cipherIds.count <= MAX_SPEC_IDS);
        require(authIds.count <= MAX_SPEC_IDS);
        require(agreeIds.count <= MAX_SPEC_IDS);
        require(sasIds.count <= MAX_SPEC_IDS);

        self.flagsUnusedLow4 = flagsUnusedLow4;
        self.flagsUnusedHigh4 = flagsUnusedHigh4;
        self.flags0SMP = flags0SMP;
        self.agreeIds = agreeIds;
        self.authIds = authIds;
        self.cipherIds = cipherIds;
        self.clientId = clientId;
        self.hashChainH3 = hashChainH3;
        self.hashIds = hashIds;
        self.sasIds = sasIds;
        self.versionId = versionId;
        self.zid = zid;
        
        HandshakePacket* unauthenticatedEmbedding = [[HandshakePacket alloc] initWithTypeId:HANDSHAKE_TYPE_HELLO
                                                                                 andPayload:[self generatePayload]];
        self.embedding = [unauthenticatedEmbedding withHMACAppended:hmacKey];
    }
    
    return self;
}

- (NSData*)generateFlags {
    NSMutableData* flags = [NSMutableData dataWithLength:FLAGS_LENGTH];
    
    [flags setUint8At:UNUSED_HIGH_AND_0SMP_FLAG_INDEX
                   to:[NumberUtil uint8FromLowUInt4:self.flagsUnusedHigh4
                                       andHighUInt4:self.flags0SMP]];
    
    [flags setUint8At:UNUSED_HIGH_AND_0SMP_FLAG_INDEX
                   to:[NumberUtil uint8FromLowUInt4:(uint8_t)self.hashIds.count
                                       andHighUInt4:self.flagsUnusedLow4]];
    
    [flags setUint8At:AUTH_ID_AND_CIPHER_ID_FLAG_INDEX
                   to:[NumberUtil uint8FromLowUInt4:(uint8_t)self.authIds.count
                                       andHighUInt4:(uint8_t)self.cipherIds.count]];
    
    [flags setUint8At:SAS_ID_AND_AGREE_ID_FLAG_INDEX
                   to:[NumberUtil uint8FromLowUInt4:(uint8_t)self.sasIds.count
                                       andHighUInt4:(uint8_t)self.agreeIds.count]];
    
    return flags;
}

- (NSData*)generatePayload {
    return [@[
            self.versionId,
            self.clientId,
            self.hashChainH3,
            self.zid.data,
            [self generateFlags],
            [[@[self.hashIds, self.cipherIds, self.authIds, self.agreeIds, self.sasIds] concatArrays] concatDatas]
            ] concatDatas];
}

- (void)verifyMacWithHashChainH2:(NSData*)hashChainH2 {
    checkOperationDescribe([[hashChainH2 hashWithSHA256] isEqualToData_TimingSafe:self.hashChainH3], @"Invalid preimage");
    [self.embedding withHMACVerifiedAndRemoved:hashChainH2];
}

- (NSData*)getVersionIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(VERSION_ID_OFFSET, VERSION_ID_LENGTH)];
}

- (NSData*)getClientIdFromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(CLIENT_ID_OFFSET, CLIENT_ID_LENGTH)];
}

- (NSData*)getHashChainH3FromPayload:(NSData*)payload {
    return [payload subdataWithRange:NSMakeRange(HASH_CHAIN_H3_OFFSET, HASH_CHAIN_ITEM_LENGTH)];
}

- (Zid*)getZidFromPayload:(NSData*)payload {
    return [[Zid alloc] initWithData:[payload subdataWithRange:NSMakeRange(ZID_OFFSET, ZID_LENGTH)]];
}

- (NSArray*)getSpecIdsFromPayload:(NSData*)payload counts:(NSArray*)counts {
    checkOperation(payload.length >= SPEC_IDS_OFFSET + SPEC_ID_LENGTH*[counts sumNSUInteger]);
    
    NSMutableArray* result = [[NSMutableArray alloc] init];
    NSUInteger offset = SPEC_IDS_OFFSET;
    for (NSNumber* count in counts) {
        NSMutableArray* subResult = [[NSMutableArray alloc] init];
        for (NSUInteger i = 0; i < [count unsignedIntegerValue]; i++) {
            [subResult addObject:[payload subdataWithRange:NSMakeRange(offset, SPEC_ID_LENGTH)]];
            offset += SPEC_ID_LENGTH;
        }
        [result addObject:subResult];
    }
    return result;
}

- (void)setFlagsAndSpecIdsFromPayload:(NSData*)payload {
    NSData* flags = [payload subdataWithRange:NSMakeRange(FLAGS_OFFSET, FLAGS_LENGTH)];

    self.flags0SMP         = [flags highUint4AtByteOffset:UNUSED_HIGH_AND_0SMP_FLAG_INDEX];
    self.flagsUnusedHigh4  = [flags lowUint4AtByteOffset:UNUSED_HIGH_AND_0SMP_FLAG_INDEX];
    self.flagsUnusedLow4   = [flags highUint4AtByteOffset:HASH_ID_AND_UNUSED_LOW_FLAG_INDEX];

    uint8_t hashIdsCount   = [flags lowUint4AtByteOffset:HASH_ID_AND_UNUSED_LOW_FLAG_INDEX];
    uint8_t cipherIdsCount = [flags highUint4AtByteOffset:AUTH_ID_AND_CIPHER_ID_FLAG_INDEX];
    uint8_t authIdsCount   = [flags lowUint4AtByteOffset:AUTH_ID_AND_CIPHER_ID_FLAG_INDEX];
    uint8_t agreeIdsCount  = [flags highUint4AtByteOffset:SAS_ID_AND_AGREE_ID_FLAG_INDEX];
    uint8_t sasIdsCount    = [flags lowUint4AtByteOffset:SAS_ID_AND_AGREE_ID_FLAG_INDEX];
    NSArray* counts = @[@(hashIdsCount),
                        @(cipherIdsCount),
                        @(authIdsCount),
                        @(agreeIdsCount),
                        @(sasIdsCount)];
    
    NSArray* specIds = [self getSpecIdsFromPayload:payload counts:counts];
    self.hashIds   = specIds[HASH_IDS_INDEX];
    self.cipherIds = specIds[CIPHER_IDS_INDEX];
    self.authIds   = specIds[AUTH_IDS_INDEX];
    self.agreeIds  = specIds[AGREE_IDS_INDEX];
    self.sasIds    = specIds[SAS_IDS_INDEX];
}

- (instancetype)initFromHandshakePacket:(HandshakePacket*)handshakePacket {
    if (self = [super init]) {
        require(handshakePacket != nil);
        checkOperationDescribe([[handshakePacket typeId] isEqualToData:HANDSHAKE_TYPE_HELLO], @"Not a hello packet");
        
        NSData* payload = [handshakePacket payload];
        checkOperation(payload.length >= SPEC_IDS_OFFSET);
        
        self.versionId = [self getVersionIdFromPayload:payload];
        self.clientId = [self getClientIdFromPayload:payload];
        self.hashChainH3 = [self getHashChainH3FromPayload:payload];
        self.zid = [self getZidFromPayload:payload];
        [self setFlagsAndSpecIdsFromPayload:payload];
        
        self.embedding = handshakePacket;
    }
    
    return self;
}

- (NSArray*)agreeIdsIncludingImplied {
    NSMutableArray* a = [self.agreeIds mutableCopy];
    [a addObject:COMMIT_DEFAULT_AGREE_SPEC_ID];
    return a;
}

@end

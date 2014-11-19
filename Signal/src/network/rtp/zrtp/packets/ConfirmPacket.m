#import "ConfirmPacket.h"
#import "Util.h"
#import "NSData+Conversions.h"
#import "NSData+CryptoTools.h"

#define TRUNCATED_HMAC_LENGTH 8
#define CONFIRM_IV_LENGTH 16
#define WORD_LENGTH 4

@interface ConfirmPacket ()

@property (strong, readwrite, atomic) NSData* confirmMac;
@property (strong, readwrite, atomic) NSData* iv;
@property (strong, readwrite, atomic) NSData* hashChainH0;
@property (readwrite, atomic) uint32_t unusedAndSignatureLengthAndFlags;
@property (readwrite, atomic) uint32_t cacheExperationInterval;
@property (readwrite, atomic) bool isPartOne;

@property (strong, readwrite, nonatomic, getter=embeddedIntoHandshakePacket) HandshakePacket* embedding;

@end

@implementation ConfirmPacket

+ (instancetype)packetOneWithHashChain:(HashChain*)hashChain
                             andMacKey:(NSData*)macKey
                          andCipherKey:(NSData*)cipherKey
                                 andIV:(NSData*)iv {
    return [[self alloc] initWithHashChainH0:hashChain.h0
         andUnusedAndSignatureLengthAndFlags:0
                  andCacheExpirationInterval:0xFFFFFFFF
                                   andMacKey:macKey
                                andCipherKey:cipherKey
                                       andIV:iv
                                andIsPartOne:true];
}

+ (instancetype)packetTwoWithHashChain:(HashChain*)hashChain
                             andMacKey:(NSData*)macKey
                          andCipherKey:(NSData*)cipherKey
                                 andIV:(NSData*)iv {
    return [[self alloc] initWithHashChainH0:hashChain.h0
         andUnusedAndSignatureLengthAndFlags:0
                  andCacheExpirationInterval:0xFFFFFFFF
                                   andMacKey:macKey
                                andCipherKey:cipherKey
                                       andIV:iv
                                andIsPartOne:false];
}

+ (instancetype)packetParsedFromHandshakePacket:(HandshakePacket*)handshakePacket
                                     withMacKey:(NSData*)macKey
                                   andCipherKey:(NSData*)cipherKey
                                   andIsPartOne:(bool)isPartOne {
    require(handshakePacket != nil);
    require(macKey != nil);
    require(cipherKey != nil);
    NSData* expectedConfirmTypeId = isPartOne ? HANDSHAKE_TYPE_CONFIRM_1 : HANDSHAKE_TYPE_CONFIRM_2;
    
    checkOperation([[handshakePacket typeId] isEqualToData:expectedConfirmTypeId]);
    checkOperation([[handshakePacket payload] length] == TRUNCATED_HMAC_LENGTH + CONFIRM_IV_LENGTH + HASH_CHAIN_ITEM_LENGTH + WORD_LENGTH + WORD_LENGTH);
    NSData* decryptedData = [self getDecryptedDataFromPayload:[handshakePacket payload]
                                                   withMacKey:macKey
                                                 andCipherKey:cipherKey];
    
    return [[ConfirmPacket alloc] initFromHandshakePacket:handshakePacket
                                          withHashChainH0:[self getHashChainH0FromDecryptedData:decryptedData]
                      andUnusedAndSignatureLengthAndFlags:[self getUnusedAndSignatureLengthAndFlagsFromDecryptedData:decryptedData]
                               andCacheExpirationInterval:[self getCacheExpirationIntervalFromDecryptedData:decryptedData]
                                          andIncludedHMAC:[self getIncludedHMACFromPayload:[handshakePacket payload]]
                                                    andIV:[self getIvFromPayload:[handshakePacket payload]]
                                             andIsPartOne:isPartOne];
}

- (instancetype)initWithHashChainH0:(NSData*)hashChainH0
andUnusedAndSignatureLengthAndFlags:(uint32_t)unused
         andCacheExpirationInterval:(uint32_t)cacheExpirationInterval
                          andMacKey:(NSData*)macKey
                       andCipherKey:(NSData*)cipherKey
                              andIV:(NSData*)iv
                       andIsPartOne:(bool)isPartOne {
    if (self = [super init]) {
        require(macKey != nil);
        require(cipherKey != nil);
        require(hashChainH0 != nil);
        require(iv != nil);
        require(iv.length == CONFIRM_IV_LENGTH);
        require(hashChainH0.length == HASH_CHAIN_ITEM_LENGTH);
        
        self.hashChainH0 = hashChainH0;
        self.unusedAndSignatureLengthAndFlags = unused;
        self.cacheExperationInterval = cacheExpirationInterval;
        self.iv = iv;
        self.isPartOne = isPartOne;
        self.embedding = [self generateEmbedding:cipherKey andMacKey:macKey];
    }
    
    return self;
}

- (HandshakePacket*)generateEmbedding:(NSData*)cipherKey
                            andMacKey:(NSData*)macKey {
    require(cipherKey != nil);
    require(macKey != nil);
    
    NSData* sensitiveData = [@[
                             self.hashChainH0,
                             [NSData dataWithBigEndianBytesOfUInt32:self.unusedAndSignatureLengthAndFlags],
                             [NSData dataWithBigEndianBytesOfUInt32:self.cacheExperationInterval]
                             ] concatDatas];
    
    NSData* encrytedSensitiveData = [sensitiveData encryptWithAESInCipherFeedbackModeWithKey:cipherKey andIV:self.iv];
    NSData* hmacForSensitiveData = [[encrytedSensitiveData hmacWithSHA256WithKey:macKey] take:TRUNCATED_HMAC_LENGTH];
    
    NSData* typeId = self.isPartOne ? HANDSHAKE_TYPE_CONFIRM_1 : HANDSHAKE_TYPE_CONFIRM_2;
    
    NSData* payload = [@[
                       hmacForSensitiveData,
                       self.iv,
                       encrytedSensitiveData
                       ] concatDatas];
    
    return [[HandshakePacket alloc] initWithTypeId:typeId andPayload:payload];
}

- (instancetype)initFromHandshakePacket:(HandshakePacket*)source
                        withHashChainH0:(NSData*)hashChainH0
    andUnusedAndSignatureLengthAndFlags:(uint32_t)unused
             andCacheExpirationInterval:(uint32_t)cacheExpirationInterval
                        andIncludedHMAC:(NSData*)includedHMAC
                                  andIV:(NSData*)iv
                           andIsPartOne:(bool)isPartOne {
    if (self = [super init]) {
        self.hashChainH0                      = hashChainH0;
        self.unusedAndSignatureLengthAndFlags = unused;
        self.cacheExperationInterval          = cacheExpirationInterval;
        self.iv                               = iv;
        self.isPartOne                          = isPartOne;
        self.confirmMac                       = includedHMAC;
        self.embedding                        = source;
    }

    return self;
}

+ (NSData*)getIncludedHMACFromPayload:(NSData*)payload {
    return [payload take:TRUNCATED_HMAC_LENGTH];
}

+ (NSData*)getIvFromPayload:(NSData*)payload {
    return [payload subdataVolatileWithRange:NSMakeRange(TRUNCATED_HMAC_LENGTH, CONFIRM_IV_LENGTH)];
}

+ (NSData*)getVolatileEncryptedDataFromPayload:(NSData*)payload {
    return [payload skipVolatile:TRUNCATED_HMAC_LENGTH + CONFIRM_IV_LENGTH];
}

+ (NSData*)getDecryptedDataFromPayload:(NSData*)payload
                            withMacKey:(NSData*)macKey
                          andCipherKey:(NSData*)cipherKey {
    
    NSData* iv = [self getIvFromPayload:payload];
    NSData* volatileEncryptedData = [self getVolatileEncryptedDataFromPayload:payload];
    NSData* includedHMAC = [self getIncludedHMACFromPayload:payload];
    
    NSData* expectedHMAC = [[volatileEncryptedData hmacWithSHA256WithKey:macKey] take:TRUNCATED_HMAC_LENGTH];
    checkOperation([includedHMAC isEqualToData_TimingSafe:expectedHMAC]);
    
    return [volatileEncryptedData decryptWithAESInCipherFeedbackModeWithKey:cipherKey andIV:iv];
}

+ (NSData*)getHashChainH0FromDecryptedData:(NSData*)decryptedData {
    return [decryptedData take:HASH_CHAIN_ITEM_LENGTH];
}

+ (uint32_t)getUnusedAndSignatureLengthAndFlagsFromDecryptedData:(NSData*)decryptedData {
    return [decryptedData bigEndianUInt32At:HASH_CHAIN_ITEM_LENGTH];
}

+ (uint32_t)getCacheExpirationIntervalFromDecryptedData:(NSData*)decryptedData {
    return [decryptedData bigEndianUInt32At:HASH_CHAIN_ITEM_LENGTH+WORD_LENGTH];
}

@end

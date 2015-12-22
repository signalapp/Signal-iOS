#import "ConfirmPacket.h"

@implementation ConfirmPacket

@synthesize confirmMac, hashChainH0, unusedAndSignatureLengthAndFlags, cacheExperationInterval, isPart1, iv;

#define TRUNCATED_HMAC_LENGTH 8
#define CONFIRM_IV_LENGTH 16
#define WORD_LENGTH 4

+(ConfirmPacket*) confirm1PacketWithHashChain:(HashChain*)hashChain
                                    andMacKey:(NSData*)macKey
                                 andCipherKey:(NSData*)cipherKey
                                        andIv:(NSData*)iv {
    return [ConfirmPacket confirmPacketWithHashChainH0:[hashChain h0]
                   andUnusedAndSignatureLengthAndFlags:0
                            andCacheExpirationInterval:0xFFFFFFFF
                                             andMacKey:macKey
                                          andCipherKey:cipherKey
                                                 andIv:iv
                                            andIsPart1:true];
}

+(ConfirmPacket*) confirm2PacketWithHashChain:(HashChain*)hashChain
                                    andMacKey:(NSData*)macKey
                                 andCipherKey:(NSData*)cipherKey
                                        andIv:(NSData*)iv {
    return [ConfirmPacket confirmPacketWithHashChainH0:[hashChain h0]
                   andUnusedAndSignatureLengthAndFlags:0
                            andCacheExpirationInterval:0xFFFFFFFF
                                             andMacKey:macKey
                                          andCipherKey:cipherKey
                                                 andIv:iv
                                            andIsPart1:false];
}

+(ConfirmPacket*) confirmPacketParsedFromHandshakePacket:(HandshakePacket*)handshakePacket
                                              withMacKey:(NSData*)macKey
                                            andCipherKey:(NSData*)cipherKey
                                              andIsPart1:(bool)isPart1 {
    ows_require(handshakePacket != nil);
    ows_require(macKey != nil);
    ows_require(cipherKey != nil);
    NSData* expectedConfirmTypeId = isPart1 ? HANDSHAKE_TYPE_CONFIRM_1 : HANDSHAKE_TYPE_CONFIRM_2;
    
    checkOperation([[handshakePacket typeId] isEqualToData:expectedConfirmTypeId]);
    checkOperation([[handshakePacket payload] length] == TRUNCATED_HMAC_LENGTH + CONFIRM_IV_LENGTH + HASH_CHAIN_ITEM_LENGTH + WORD_LENGTH + WORD_LENGTH);
    NSData* decryptedData = [self getDecryptedDataFromPayload:[handshakePacket payload] withMacKey:macKey andCipherKey:cipherKey];
    
    return [ConfirmPacket confirmPacketParsedFrom:handshakePacket
                                  withHashChainH0:[self getHashChainH0FromDecryptedData:decryptedData]
              andUnusedAndSignatureLengthAndFlags:[self getUnusedAndSignatureLengthAndFlagsFromDecryptedData:decryptedData]
                       andCacheExpirationInterval:[self getCacheExpirationIntervalFromDecryptedData:decryptedData]
                                  andIncludedHmac:[self getIncludedHmacFromPayload:[handshakePacket payload]]
                                            andIv:[self getIvFromPayload:[handshakePacket payload]]
                                       andIsPart1:isPart1];
}
+(ConfirmPacket*) confirmPacketWithHashChainH0:(NSData*)hashChainH0
           andUnusedAndSignatureLengthAndFlags:(uint32_t)unused
                    andCacheExpirationInterval:(uint32_t)cacheExpirationInterval
                                     andMacKey:(NSData*)macKey
                                  andCipherKey:(NSData*)cipherKey
                                         andIv:(NSData*)iv
                                    andIsPart1:(bool)isPart1 {
    ows_require(macKey != nil);
    ows_require(cipherKey != nil);
    ows_require(hashChainH0 != nil);
    ows_require(iv != nil);
    ows_require(iv.length == CONFIRM_IV_LENGTH);
    ows_require(hashChainH0.length == HASH_CHAIN_ITEM_LENGTH);
    
    ConfirmPacket* p = [ConfirmPacket new];
    p->hashChainH0 = hashChainH0;
    p->unusedAndSignatureLengthAndFlags = unused;
    p->cacheExperationInterval = cacheExpirationInterval;
    p->iv = iv;
    p->isPart1 = isPart1;
    p->embedding = [p generateEmbedding:cipherKey andMacKey:macKey];
    return p;
}

-(HandshakePacket*) generateEmbedding:(NSData*)cipherKey andMacKey:(NSData*)macKey {
    ows_require(cipherKey != nil);
    ows_require(macKey != nil);
    
    NSData* sensitiveData = [@[
                             hashChainH0,
                             [NSData dataWithBigEndianBytesOfUInt32:unusedAndSignatureLengthAndFlags],
                             [NSData dataWithBigEndianBytesOfUInt32:cacheExperationInterval]
                             ] ows_concatDatas];
    
    NSData* encrytedSensitiveData = [sensitiveData encryptWithAesInCipherFeedbackModeWithKey:cipherKey andIv:iv];
    NSData* hmacForSensitiveData = [[encrytedSensitiveData hmacWithSha256WithKey:macKey] take:TRUNCATED_HMAC_LENGTH];
    
    NSData* typeId = isPart1 ? HANDSHAKE_TYPE_CONFIRM_1 : HANDSHAKE_TYPE_CONFIRM_2;
    
    NSData* payload = [@[
                       hmacForSensitiveData,
                       iv,
                       encrytedSensitiveData
                       ] ows_concatDatas];
    
    return [HandshakePacket handshakePacketWithTypeId:typeId andPayload:payload];
}

+(ConfirmPacket*) confirmPacketParsedFrom:(HandshakePacket*)source
                          withHashChainH0:(NSData*)hashChainH0
      andUnusedAndSignatureLengthAndFlags:(uint32_t)unused
               andCacheExpirationInterval:(uint32_t)cacheExpirationInterval
                          andIncludedHmac:(NSData*)includedHmac
                                    andIv:(NSData*)iv
                               andIsPart1:(bool)isPart1 {
    
    ConfirmPacket* p = [ConfirmPacket new];
    
    p->hashChainH0 = hashChainH0;
    p->unusedAndSignatureLengthAndFlags = unused;
    p->cacheExperationInterval = cacheExpirationInterval;
    p->iv = iv;
    p->isPart1 = isPart1;
    p->confirmMac = includedHmac;
    p->embedding = source;
    return p;
    
}

+(NSData*) getIncludedHmacFromPayload:(NSData*)payload {
    return [payload take:TRUNCATED_HMAC_LENGTH];
}
+(NSData*) getIvFromPayload:(NSData*)payload {
    return [payload subdataVolatileWithRange:NSMakeRange(TRUNCATED_HMAC_LENGTH, CONFIRM_IV_LENGTH)];
}
+(NSData*) getVolatileEncryptedDataFromPayload:(NSData*)payload {
    return [payload skipVolatile:TRUNCATED_HMAC_LENGTH + CONFIRM_IV_LENGTH];
}
+(NSData*) getDecryptedDataFromPayload:(NSData*)payload
                            withMacKey:(NSData*)macKey
                          andCipherKey:(NSData*)cipherKey {
    
    NSData* iv = [self getIvFromPayload:payload];
    NSData* volatileEncryptedData = [self getVolatileEncryptedDataFromPayload:payload];
    NSData* includedHmac = [self getIncludedHmacFromPayload:payload];
    
    NSData* expectedHmac = [[volatileEncryptedData hmacWithSha256WithKey:macKey] take:TRUNCATED_HMAC_LENGTH];
    checkOperation([includedHmac isEqualToData_TimingSafe:expectedHmac]);
    
    return [volatileEncryptedData decryptWithAesInCipherFeedbackModeWithKey:cipherKey andIv:iv];
}
+(NSData*) getHashChainH0FromDecryptedData:(NSData*)decryptedData {
    return [decryptedData take:HASH_CHAIN_ITEM_LENGTH];
}
+(uint32_t) getUnusedAndSignatureLengthAndFlagsFromDecryptedData:(NSData*)decryptedData {
    return [decryptedData bigEndianUInt32At:HASH_CHAIN_ITEM_LENGTH];
}
+(uint32_t) getCacheExpirationIntervalFromDecryptedData:(NSData*)decryptedData {
    return [decryptedData bigEndianUInt32At:HASH_CHAIN_ITEM_LENGTH+WORD_LENGTH];
}

-(HandshakePacket*) embeddedIntoHandshakePacket {
    return embedding;
}

@end

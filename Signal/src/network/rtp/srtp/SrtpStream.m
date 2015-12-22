#import "SrtpStream.h"
#import "Util.h"

#define HMAC_LENGTH 20
#define IV_SALT_LENGTH 14
#define IV_LENGTH 16

@implementation SrtpStream

+(SrtpStream*) srtpStreamWithCipherKey:(NSData*)cipherKey andMacKey:(NSData*)macKey andCipherIvSalt:(NSData*)cipherIvSalt {
    ows_require(cipherKey != nil);
    ows_require(macKey != nil);
    ows_require(cipherIvSalt != nil);
    ows_require(cipherIvSalt.length == IV_SALT_LENGTH);

    SrtpStream* s = [SrtpStream new];
    s->cipherIvSalt = cipherIvSalt;
    s->macKey = macKey;
    s->cipherKey = cipherKey;
    s->sequenceCounter = [SequenceCounter sequenceCounter];
    return s;
}

-(RtpPacket*) encryptAndAuthenticateNormalRtpPacket:(RtpPacket*)normalRtpPacket {
    ows_require(normalRtpPacket != nil);
    NSData* payload = [normalRtpPacket payload];

    NSData* iv = [self getIvForSequenceNumber:[normalRtpPacket sequenceNumber] andSynchronizationSourceIdentifier:[normalRtpPacket synchronizationSourceIdentifier]];
    NSData* encryptedPayload = [payload encryptWithAesInCounterModeWithKey:cipherKey andIv:iv];

    RtpPacket* encryptedRtpPacket = [normalRtpPacket withPayload:encryptedPayload];
    NSData* hmac = [[encryptedRtpPacket rawPacketDataUsingInteropOptions:@[]] hmacWithSha1WithKey:macKey];
    NSData* authenticatedEncryptedPayload = [@[encryptedPayload, hmac] ows_concatDatas];

    return [encryptedRtpPacket withPayload:authenticatedEncryptedPayload];
}

-(RtpPacket*) verifyAuthenticationAndDecryptSecuredRtpPacket:(RtpPacket*)securedRtpPacket {
    ows_require(securedRtpPacket != nil);
    checkOperationDescribe([[securedRtpPacket payload] length] >= HMAC_LENGTH, @"Payload not long enough to include hmac");

    NSData* authenticatedData = [securedRtpPacket rawPacketDataUsingInteropOptions:nil];
    NSData* includedHmac = [authenticatedData takeLastVolatile:HMAC_LENGTH];
    NSData* expectedHmac = [[authenticatedData skipLastVolatile:HMAC_LENGTH] hmacWithSha1WithKey:macKey];
    checkOperationDescribe(expectedHmac.length == HMAC_LENGTH, @"Hmac length constant is wrong");
    checkOperationDescribe([includedHmac isEqualToData_TimingSafe:expectedHmac], @"Authentication failed.");

    NSData* iv = [self getIvForSequenceNumber:[securedRtpPacket sequenceNumber] andSynchronizationSourceIdentifier:[securedRtpPacket synchronizationSourceIdentifier]];
    NSData* encryptedPayload = [[securedRtpPacket payload] skipLastVolatile:HMAC_LENGTH];
    NSData* decryptedPayload = [encryptedPayload decryptWithAesInCounterModeWithKey:cipherKey andIv:iv];

    return [securedRtpPacket withPayload:decryptedPayload];
}

-(NSData*)getIvForSequenceNumber:(uint16_t)sequenceNumber andSynchronizationSourceIdentifier:(uint64_t)synchronizationSourceIdentifier {
    int64_t logicalSequence = [sequenceCounter convertNext:sequenceNumber];
    NSMutableData* iv       = [NSMutableData dataWithLength:IV_LENGTH];

    [iv replaceBytesStartingAt:0 withData:cipherIvSalt];
    uint8_t* b = (uint8_t*)[iv bytes];

    b[6]  ^= (uint8_t)((synchronizationSourceIdentifier >> 8) & 0xFF);
    b[7]  ^= (uint8_t)((synchronizationSourceIdentifier >> 0) & 0xFF);
    b[8]  ^= (uint8_t)((logicalSequence >> 40) & 0xFF);
    b[9]  ^= (uint8_t)((logicalSequence >> 32) & 0xFF);
    b[10] ^= (uint8_t)((logicalSequence >> 24) & 0xFF);
    b[11] ^= (uint8_t)((logicalSequence >> 16) & 0xFF);
    b[12] ^= (uint8_t)((logicalSequence >> 8) & 0xFF);
    b[13] ^= (uint8_t)((logicalSequence >> 0) & 0xFF);

    return iv;
}

@end

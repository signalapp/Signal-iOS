#import "SRTPStream.h"
#import "Util.h"
#import "NSData+CryptoTools.h"

#define HMAC_LENGTH 20
#define IV_SALT_LENGTH 14
#define IV_LENGTH 16

@interface SRTPStream ()

@property (strong, nonatomic) NSData* cipherKey;
@property (strong, nonatomic) NSData* cipherIVSalt;
@property (strong, nonatomic) NSData* macKey;
@property (strong, nonatomic) SequenceCounter* sequenceCounter;

@end

@implementation SRTPStream

- (instancetype)initWithCipherKey:(NSData*)cipherKey
                        andMacKey:(NSData*)macKey
                  andCipherIVSalt:(NSData*)cipherIVSalt {
    if (self = [super init]) {
        require(cipherKey != nil);
        require(macKey != nil);
        require(cipherIVSalt != nil);
        require(cipherIVSalt.length == IV_SALT_LENGTH);
        
        self.cipherIVSalt = cipherIVSalt;
        self.macKey = macKey;
        self.cipherKey = cipherKey;
        self.sequenceCounter = [[SequenceCounter alloc] init];
    }
    
    return self;
}

- (RTPPacket*)encryptAndAuthenticateNormalRTPPacket:(RTPPacket*)normalRTPPacket {
    require(normalRTPPacket != nil);
    NSData* payload = [normalRTPPacket payload];

    NSData* iv = [self getIvForSequenceNumber:[normalRTPPacket sequenceNumber]
           andSynchronizationSourceIdentifier:[normalRTPPacket synchronizationSourceIdentifier]];
    NSData* encryptedPayload = [payload encryptWithAESInCounterModeWithKey:self.cipherKey andIV:iv];

    RTPPacket* encryptedRTPPacket = [normalRTPPacket withPayload:encryptedPayload];
    NSData* hmac = [[encryptedRTPPacket rawPacketDataUsingInteropOptions:@[]] hmacWithSHA1WithKey:self.macKey];
    NSData* authenticatedEncryptedPayload = [@[encryptedPayload, hmac] concatDatas];

    return [encryptedRTPPacket withPayload:authenticatedEncryptedPayload];
}

- (RTPPacket*)verifyAuthenticationAndDecryptSecuredRTPPacket:(RTPPacket*)securedRTPPacket {
    require(securedRTPPacket != nil);
    checkOperationDescribe([[securedRTPPacket payload] length] >= HMAC_LENGTH, @"Payload not long enough to include hmac");

    NSData* authenticatedData = [securedRTPPacket rawPacketDataUsingInteropOptions:nil];
    NSData* includedHMAC = [authenticatedData takeLastVolatile:HMAC_LENGTH];
    NSData* expectedHMAC = [[authenticatedData skipLastVolatile:HMAC_LENGTH] hmacWithSHA1WithKey:self.macKey];
    checkOperationDescribe(expectedHMAC.length == HMAC_LENGTH, @"HMAC length constant is wrong");
    checkOperationDescribe([includedHMAC isEqualToData_TimingSafe:expectedHMAC], @"Authentication failed.");

    NSData* iv = [self getIvForSequenceNumber:[securedRTPPacket sequenceNumber] andSynchronizationSourceIdentifier:[securedRTPPacket synchronizationSourceIdentifier]];
    NSData* encryptedPayload = [[securedRTPPacket payload] skipLastVolatile:HMAC_LENGTH];
    NSData* decryptedPayload = [encryptedPayload decryptWithAESInCounterModeWithKey:self.cipherKey andIV:iv];

    return [securedRTPPacket withPayload:decryptedPayload];
}

- (NSData*)getIvForSequenceNumber:(uint16_t)sequenceNumber andSynchronizationSourceIdentifier:(uint64_t)synchronizationSourceIdentifier {
    int64_t logicalSequence = [self.sequenceCounter convertNext:sequenceNumber];
    NSMutableData* iv       = [NSMutableData dataWithLength:IV_LENGTH];

    [iv replaceBytesStartingAt:0 withData:self.cipherIVSalt];
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

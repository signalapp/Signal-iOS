#import "DHPacket.h"
#import "Util.h"
#import "CryptoTools.h"
#import "NSData+CryptoTools.h"

#define     H1_PAYLOAD_OFFSET           0
#define    RS1_PAYLOAD_OFFSET           DH_HASH_CHAIN_H1_LENGTH
#define    RS2_PAYLOAD_OFFSET           RS1_PAYLOAD_OFFSET + DH_RS1_LENGTH
#define    AUX_PAYLOAD_OFFSET           RS2_PAYLOAD_OFFSET + DH_RS2_LENGTH
#define    PBX_PAYLOAD_OFFSET           AUX_PAYLOAD_OFFSET + DH_AUX_LENGTH
#define PUBKEY_PAYLOAD_OFFSET           PBX_PAYLOAD_OFFSET + DH_PBX_LENGTH

#define MIN_DH_PKT_LENGTH (PUBKEY_PAYLOAD_OFFSET + HANDSHAKE_TRUNCATED_HMAC_LENGTH)

@interface DHPacket ()

@property (readwrite, nonatomic) bool isPart1;
@property (strong, readwrite, nonatomic) DHPacketSharedSecretHashes* sharedSecretHashes;
@property (strong, readwrite, nonatomic) NSData* publicKeyData;
@property (strong, readwrite, nonatomic) NSData* hashChainH1;

@property (strong, readwrite, nonatomic, getter=embeddedIntoHandshakePacket) HandshakePacket* embedding;

@end

@implementation DHPacket

+ (DHPacket*)dh1PacketWithHashChain:(HashChain*)hashChain
              andSharedSecretHashes:(DHPacketSharedSecretHashes*)sharedSecretHashes
                       andKeyAgreer:(id<KeyAgreementParticipant>)agreer {
    
    require(hashChain != nil);
    require(sharedSecretHashes != nil);
    require(agreer != nil);
    
    return [[DHPacket alloc] initWithHashChainH0:hashChain.h0
                           andSharedSecretHashes:sharedSecretHashes
                                andPublicKeyData:[agreer getPublicKeyData]
                                      andIsPart1:true];
}

+ (DHPacket*)dh2PacketWithHashChain:(HashChain*)hashChain
              andSharedSecretHashes:(DHPacketSharedSecretHashes*)sharedSecretHashes
                       andKeyAgreer:(id<KeyAgreementParticipant>)agreer {
    
    require(hashChain != nil);
    require(sharedSecretHashes != nil);
    require(agreer != nil);
    
    return [[DHPacket alloc] initWithHashChainH0:hashChain.h0
                           andSharedSecretHashes:sharedSecretHashes
                                andPublicKeyData:[agreer getPublicKeyData]
                                      andIsPart1:false];
}

- (instancetype)initWithHashChainH0:(NSData*)hashChainH0
              andSharedSecretHashes:(DHPacketSharedSecretHashes*)sharedSecretHashes
                   andPublicKeyData:(NSData*)publicKeyData
                         andIsPart1:(bool)isPart1 {
    if (self = [super init]) {
        require(hashChainH0 != nil);
        require(sharedSecretHashes != nil);
        require(publicKeyData != nil);
        require(hashChainH0.length == HASH_CHAIN_ITEM_LENGTH);
        
        self.isPart1 = isPart1;
        self.hashChainH1 = [hashChainH0 hashWithSHA256];
        self.sharedSecretHashes = sharedSecretHashes;
        self.publicKeyData = publicKeyData;
        self.embedding = [self embedIntoHandshakePacketAuthenticatedWithMacKey:hashChainH0];
    }
    
    return self;
}

- (void)verifyMacWithHashChainH0:(NSData*)hashChainH0 {
    checkOperation([[hashChainH0 hashWithSHA256] isEqualToData_TimingSafe:self.hashChainH1]);
    [self.embedding withHMACVerifiedAndRemoved:hashChainH0];
}

- (NSData*)getHashChainH1FromPayload:(NSData*)payload {
    return [payload take:HASH_CHAIN_ITEM_LENGTH];
}

- (DHPacketSharedSecretHashes*)getSharedSecretHashesFromPayload:(NSData*)payload {
    
    NSData* rs1     = [payload subdataWithRange:NSMakeRange(RS1_PAYLOAD_OFFSET, DH_RS1_LENGTH)];
    NSData* rs2     = [payload subdataWithRange:NSMakeRange(RS2_PAYLOAD_OFFSET, DH_RS2_LENGTH)];
    NSData* aux     = [payload subdataWithRange:NSMakeRange(AUX_PAYLOAD_OFFSET, DH_AUX_LENGTH)];
    NSData* pbx     = [payload subdataWithRange:NSMakeRange(PBX_PAYLOAD_OFFSET, DH_PBX_LENGTH)];
    
    return [[DHPacketSharedSecretHashes alloc] initWithRs1:rs1 andRs2:rs2 andAux:aux andPbx:pbx];
}

- (NSData*)getPublicKeyDataFromPayload:(NSData*)payload {
    return [[payload skip:PUBKEY_PAYLOAD_OFFSET] skipLast:HANDSHAKE_TRUNCATED_HMAC_LENGTH];
}

- (instancetype)initFromHandshakePacket:(HandshakePacket*)handshakePacket
                         andIsPart1:(bool)isPart1 {
    if (self = [super init]) {
        require(handshakePacket != nil);
        NSData* expectedTypeIdDHPacket = isPart1 ? HANDSHAKE_TYPE_DH_1 : HANDSHAKE_TYPE_DH_2;
        NSData* payload = [handshakePacket payload];
        
        checkOperation([[handshakePacket typeId] isEqualToData:expectedTypeIdDHPacket]);
        checkOperation(payload.length >= MIN_DH_PKT_LENGTH);
        
        self.hashChainH1        = [self getHashChainH1FromPayload:payload];
        self.sharedSecretHashes = [self getSharedSecretHashesFromPayload:payload];
        self.publicKeyData      = [self getPublicKeyDataFromPayload:payload];
        self.embedding          = handshakePacket;
    }
    
    return self;
}

- (HandshakePacket*)embedIntoHandshakePacketAuthenticatedWithMacKey:(NSData*)macKey {
    require(macKey != nil);
    requireState(self.hashChainH1.length == HASH_CHAIN_ITEM_LENGTH);
    
    NSData* typeId = self.isPart1 ? HANDSHAKE_TYPE_DH_1 : HANDSHAKE_TYPE_DH_2;
    
    NSData* payload = [@[
                       self.hashChainH1,
                       self.sharedSecretHashes.rs1,
                       self.sharedSecretHashes.rs2,
                       self.sharedSecretHashes.aux,
                       self.sharedSecretHashes.pbx,
                       self.publicKeyData
                       ] concatDatas];
    
    return [[[HandshakePacket alloc] initWithTypeId:typeId andPayload:payload] withHMACAppended:macKey];
}

@end

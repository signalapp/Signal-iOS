#import "DhPacket.h"

@implementation DhPacket

#define     H1_PAYLOAD_OFFSET           0
#define    RS1_PAYLOAD_OFFSET           DH_HASH_CHAIN_H1_LENGTH
#define    RS2_PAYLOAD_OFFSET           RS1_PAYLOAD_OFFSET + DH_RS1_LENGTH
#define    AUX_PAYLOAD_OFFSET           RS2_PAYLOAD_OFFSET + DH_RS2_LENGTH
#define    PBX_PAYLOAD_OFFSET           AUX_PAYLOAD_OFFSET + DH_AUX_LENGTH
#define PUBKEY_PAYLOAD_OFFSET           PBX_PAYLOAD_OFFSET + DH_PBX_LENGTH

#define MIN_DH_PKT_LENGTH (PUBKEY_PAYLOAD_OFFSET + HANDSHAKE_TRUNCATED_HMAC_LENGTH)

@synthesize hashChainH1, isPart1, publicKeyData, sharedSecretHashes;

+(DhPacket*) dh1PacketWithHashChain:(HashChain*)hashChain
              andSharedSecretHashes:(DhPacketSharedSecretHashes*)sharedSecretHashes
                       andKeyAgreer:(id<KeyAgreementParticipant>)agreer {
    
    ows_require(hashChain != nil);
    ows_require(sharedSecretHashes != nil);
    ows_require(agreer != nil);
    
    return [self dhPacketWithHashChainH0:[hashChain h0]
                   andSharedSecretHashes:sharedSecretHashes
                        andPublicKeyData:agreer.getPublicKeyData
                              andIsPart1:true];
}

+(DhPacket*) dh2PacketWithHashChain:(HashChain*)hashChain
              andSharedSecretHashes:(DhPacketSharedSecretHashes*)sharedSecretHashes
                       andKeyAgreer:(id<KeyAgreementParticipant>)agreer {
    
    ows_require(hashChain != nil);
    ows_require(sharedSecretHashes != nil);
    ows_require(agreer != nil);
    
    return [self dhPacketWithHashChainH0:[hashChain h0]
                   andSharedSecretHashes:sharedSecretHashes
                        andPublicKeyData:agreer.getPublicKeyData
                              andIsPart1:false];
}

+(DhPacket*) dhPacketWithHashChainH0:(NSData*)hashChainH0
               andSharedSecretHashes:(DhPacketSharedSecretHashes*)sharedSecretHashes
                    andPublicKeyData:(NSData*)publicKeyData
                          andIsPart1:(bool)isPart1 {
    
    ows_require(hashChainH0 != nil);
    ows_require(sharedSecretHashes != nil);
    ows_require(publicKeyData != nil);
    
    ows_require(hashChainH0.length == HASH_CHAIN_ITEM_LENGTH);
    
    DhPacket* p = [DhPacket new];
    p->isPart1 = isPart1;
    p->hashChainH1 = [hashChainH0 hashWithSha256];
    p->sharedSecretHashes = sharedSecretHashes;
    p->publicKeyData = publicKeyData;
    p->embedding = [p embedIntoHandshakePacketAuthenticatedWithMacKey:hashChainH0];
    return p;
}

-(void) verifyMacWithHashChainH0:(NSData*)hashChainH0 {
    checkOperation([[hashChainH0 hashWithSha256] isEqualToData_TimingSafe:hashChainH1]);
    [embedding withHmacVerifiedAndRemoved:hashChainH0];
}

+(NSData*) getHashChainH1FromPayload:(NSData*)payload {
    return [payload take:HASH_CHAIN_ITEM_LENGTH];
}

+(DhPacketSharedSecretHashes*) getSharedSecretHashesFromPayload:(NSData*)payload {
    
    NSData* rs1     = [payload subdataWithRange:NSMakeRange(RS1_PAYLOAD_OFFSET, DH_RS1_LENGTH)];
    NSData* rs2     = [payload subdataWithRange:NSMakeRange(RS2_PAYLOAD_OFFSET, DH_RS2_LENGTH)];
    NSData* aux     = [payload subdataWithRange:NSMakeRange(AUX_PAYLOAD_OFFSET, DH_AUX_LENGTH)];
    NSData* pbx     = [payload subdataWithRange:NSMakeRange(PBX_PAYLOAD_OFFSET, DH_PBX_LENGTH)];
    
    return [DhPacketSharedSecretHashes dhPacketSharedSecretHashesWithRs1:rs1 andRs2:rs2  andAux:aux  andPbx:pbx];
}

+(NSData*) getPublicKeyDataFromPayload:(NSData*)payload {
    return [[payload skip:PUBKEY_PAYLOAD_OFFSET] skipLast:HANDSHAKE_TRUNCATED_HMAC_LENGTH];
}

+(DhPacket*) dhPacketFromHandshakePacket:(HandshakePacket*)handshakePacket andIsPart1:(bool)isPart1 {
    
    ows_require(handshakePacket != nil);
    NSData* expectedTypeIdDhPacket = isPart1 ? HANDSHAKE_TYPE_DH_1 : HANDSHAKE_TYPE_DH_2;
    NSData* payload = [handshakePacket payload];
    
    checkOperation([[handshakePacket typeId] isEqualToData:expectedTypeIdDhPacket]);
    checkOperation(payload.length >= MIN_DH_PKT_LENGTH);
    
    DhPacket* p = [DhPacket new];
    p->hashChainH1 = [self getHashChainH1FromPayload:payload];
    p->sharedSecretHashes = [self getSharedSecretHashesFromPayload:payload];
    p->publicKeyData = [self getPublicKeyDataFromPayload:payload];
    p->embedding = handshakePacket;
    return p;
}

-(HandshakePacket*) embedIntoHandshakePacketAuthenticatedWithMacKey:(NSData*)macKey {
    ows_require(macKey != nil);
    requireState(hashChainH1.length == HASH_CHAIN_ITEM_LENGTH);
    
    NSData* typeId = isPart1 ? HANDSHAKE_TYPE_DH_1 : HANDSHAKE_TYPE_DH_2;
    
    NSData* payload = [@[
                       hashChainH1,
                       [sharedSecretHashes rs1],
                       [sharedSecretHashes rs2],
                       [sharedSecretHashes aux],
                       [sharedSecretHashes pbx],
                       publicKeyData
                       ] ows_concatDatas];
    
    return [[HandshakePacket handshakePacketWithTypeId:typeId andPayload:payload] withHmacAppended:macKey];
}

-(HandshakePacket*) embeddedIntoHandshakePacket {
    return embedding;
}

@end

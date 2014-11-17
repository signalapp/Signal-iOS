#import "ConfirmPacket.h"
#import "CryptoTools.h"
#import "NSData+CryptoTools.h"
#import "DH3KKeyAgreementProtocol.h"
#import "Constraints.h"
#import "NSArray+FunctionalUtil.h"
#import "MasterSecret.h"
#import "Util.h"
#import "ZRTPInitiator.h"
#import "PropertyListPreferences+Util.h"
#import "SGNKeychainUtil.h"

#define DHRS1_LENGTH 8
#define DHRS2_LENGTH 8
#define DHAUX_LENGTH 8
#define DHPBX_LENGTH 8
#define IV_LENGTH 16

@interface ZRTPInitiator ()

@property (strong, nonatomic) CommitPacket* commitPacket;
@property (strong, nonatomic) DHPacketSharedSecretHashes* dhSharedSecretHashes;
@property (strong, nonatomic) DHPacket* foreignDH;
@property (strong, nonatomic) DHPacket* localDH;
@property (strong, nonatomic) HashChain* hashChain;
@property (strong, nonatomic) HelloPacket* foreignHello;
@property (strong, nonatomic) HelloPacket* localHello;
@property (strong, nonatomic) id<KeyAgreementParticipant> keyAgreementParticipant;
@property (strong, nonatomic) id<OccurrenceLogger> badPacketLogger;
@property (strong, nonatomic) NSArray* allowedKeyAgreementProtocols;
@property (strong, nonatomic) NSData* confirmIV;
@property (strong, nonatomic) MasterSecret* masterSecret;
@property (nonatomic) PacketExpectation packetExpectation;
@property (strong, nonatomic) Zid* zid;
@property (strong, nonatomic) CallController* callController;

@end

@implementation ZRTPInitiator

- (instancetype)initWithCallController:(CallController*)callController {
    if (self = [super init]) {
        require(callController != nil);
        
        self.allowedKeyAgreementProtocols = Environment.getCurrent.keyAgreementProtocolsInDescendingPriority;
        self.dhSharedSecretHashes = [DHPacketSharedSecretHashes randomized];
        self.zid = [SGNKeychainUtil zid];
        self.confirmIV = [CryptoTools generateSecureRandomData:IV_LENGTH];
        self.hashChain = [[HashChain alloc] initWithSecureGeneratedData];
        self.badPacketLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"Bad Packet"];
        self.packetExpectation = EXPECTING_HELLO;
        self.callController = callController;
    }
    
    return self;
}

- (MasterSecret*)getMasterSecret {
    requireState(self.hasHandshakeFinishedSuccessfully);
    return self.masterSecret;
}

- (HandshakePacket*)initialPacket {
    return nil;
}

- (bool)hasHandshakeFinishedSuccessfully {
    return self.packetExpectation == EXPECTING_NOTHING;
}

- (HandshakePacket*)handlePacket:(HandshakePacket*)packet {
    @try {
        if      (self.packetExpectation == EXPECTING_NOTHING)     return nil;
        else if (self.packetExpectation == EXPECTING_HELLO)       return [self handleHello:packet];
        else if (self.packetExpectation == EXPECTING_HELLO_ACK)   return [self handleHelloAck:packet];
        else if (self.packetExpectation == EXPECTING_DH)          return [self handleDH:packet];
        else if (self.packetExpectation == EXPECTING_CONFIRM)     return [self handleConfirmOne:packet];
        else if (self.packetExpectation == EXPECTING_CONFIRM_ACK) return [self handleConfirmAck:packet];
        else return nil;
    
    } @catch (SecurityFailure *exception) {
        [self.callController terminateWithReason:CallTerminationTypeHandshakeFailed withFailureInfo:exception andRelatedInfo:packet];
        return nil;
    } @catch (OperationFailed* ex) {
        [self.badPacketLogger markOccurrence:ex];
        return nil;
    }
}

- (HandshakePacket*)handleHello:(HandshakePacket*)packet {
    self.foreignHello = [packet parsedAsHello];
    
    [self.callController advanceCallProgressTo:CallProgressTypeSecuring];

    self.keyAgreementParticipant = [self retrieveKeyAgreementParticpant];
    
    self.localHello   = [HelloPacket helloPacketWithDefaultsAndHashChain:self.hashChain
                                                                  andZid:self.zid
                                                andKeyAgreementProtocols:self.allowedKeyAgreementProtocols];
    
    self.packetExpectation = EXPECTING_HELLO_ACK;
    
    return [self.localHello embeddedIntoHandshakePacket];
}

- (HandshakePacket*)handleHelloAck:(HandshakePacket*)packet {
    [packet parsedAsHelloAck];
    
    [self retrieveKeyAgreementParticpant];
    
    self.localDH = [DHPacket dh2PacketWithHashChain:self.hashChain
                              andSharedSecretHashes:self.dhSharedSecretHashes
                                       andKeyAgreer:self.keyAgreementParticipant];
    
    self.commitPacket = [CommitPacket commitPacketWithDefaultSpecsAndKeyAgreementProtocol:self.keyAgreementParticipant.getProtocol
                                                                             andHashChain:self.hashChain
                                                                                   andZid:self.zid
                                                                     andCommitmentToHello:self.foreignHello
                                                                               andDHPart2:self.localDH];
    
    self.packetExpectation = EXPECTING_DH;
    
    return [self.commitPacket embeddedIntoHandshakePacket];
}

- (HandshakePacket*)handleDH:(HandshakePacket*)packet {
    self.foreignDH = [packet parsedAsDH1];
    
    [self.foreignHello verifyMacWithHashChainH2:[[self.foreignDH hashChainH1] hashWithSHA256]];
    
    NSData* dhResult = [self.keyAgreementParticipant calculateKeyAgreementAgainstRemotePublicKey:[self.foreignDH publicKeyData]];
    
    self.masterSecret = [MasterSecret masterSecretFromDHResult:dhResult
                                             andInitiatorHello:self.localHello
                                             andResponderHello:self.foreignHello
                                                     andCommit:self.commitPacket
                                                    andDhPart1:self.foreignDH
                                                    andDhPart2:self.localDH];
    
    self.packetExpectation = EXPECTING_CONFIRM;
    return [self.localDH embeddedIntoHandshakePacket];
}

- (HandshakePacket*)handleConfirmOne:(HandshakePacket*)packet {
    ConfirmPacket* confirmPacket = [packet parsedAsConfirm1AuthenticatedWithMacKey:[self.masterSecret responderMacKey]
                                                                      andCipherKey:[self.masterSecret responderZRTPKey]];
    
    NSData* preimage = [confirmPacket hashChainH0];
    [self.foreignDH verifyMacWithHashChainH0:preimage];
    
    self.packetExpectation = EXPECTING_CONFIRM_ACK;
    ConfirmPacket* confirm2Packet = [ConfirmPacket confirm2PacketWithHashChain:self.hashChain
                                                                     andMacKey:[self.masterSecret initiatorMacKey]
                                                                  andCipherKey:[self.masterSecret initiatorZRTPKey]
                                                                         andIV:self.confirmIV];
    return [confirm2Packet embeddedIntoHandshakePacket];
}

- (HandshakePacket*)handleConfirmAck:(HandshakePacket*)packet {
    [packet parsedAsConfAck];
    
    self.packetExpectation = EXPECTING_NOTHING;
    return nil;
}

- (bool)isAuthenticatedAudioDataImplyingConf2Ack:(id)packet {
    if (self.packetExpectation != EXPECTING_CONFIRM_ACK) return false;
    if (![packet isKindOfClass:[RTPPacket class]]) return false;
    
    @try {
        SRTPStream* incomingContext = [[SRTPStream alloc] initWithCipherKey:[self.masterSecret responderSrtpKey]
                                                                  andMacKey:[self.masterSecret responderMacKey]
                                                            andCipherIVSalt:[self.masterSecret responderSrtpSalt]];
        [incomingContext verifyAuthenticationAndDecryptSecuredRTPPacket:packet];
        return true;
    } @catch (OperationFailed* ex) {
        return false;
    }
}

- (id<KeyAgreementParticipant>)retrieveKeyAgreementParticpant{
    NSArray* idsOfProtocolsAllowedByPeer = [self.foreignHello agreeIdsIncludingImplied];

    id<KeyAgreementProtocol> bestCommonKeyAgreementProtocol = [self.allowedKeyAgreementProtocols firstMatchingElseNil:^int(id<KeyAgreementProtocol> locallyAllowedProtocol) {
        return [idsOfProtocolsAllowedByPeer containsObject:locallyAllowedProtocol.getId];
    }];
    
    // Note: should never fail to find a common protocol because DH3k support is required and implied
    checkOperation(bestCommonKeyAgreementProtocol != nil);

    return [bestCommonKeyAgreementProtocol generateParticipantWithNewKeys];
}

- (SRTPSocket*)useKeysToSecureRTPSocket:(RTPSocket*)rtpSocket {
    requireState(self.hasHandshakeFinishedSuccessfully);
    return [[SRTPSocket alloc] initOverRTP:rtpSocket
                      andIncomingCipherKey:[self.masterSecret responderSrtpKey]
                         andIncomingMacKey:[self.masterSecret responderMacKey]
                           andIncomingSalt:[self.masterSecret responderSrtpSalt]
                      andOutgoingCipherKey:[self.masterSecret initiatorSrtpKey]
                         andOutgoingMacKey:[self.masterSecret initiatorMacKey]
                           andOutgoingSalt:[self.masterSecret initiatorSrtpSalt]];
}

@end

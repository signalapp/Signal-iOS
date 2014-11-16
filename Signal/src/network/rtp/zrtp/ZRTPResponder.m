#import "CommitPacket.h"
#import "ConfirmPacket.h"
#import "DH3KKeyAgreementProtocol.h"
#import "PreferencesUtil.h"
#import "NSArray+FunctionalUtil.h"
#import "MasterSecret.h"
#import "Util.h"
#import "ZRTPResponder.h"
#import "HelloAckPacket.h"
#import "ConfirmAckPacket.h"
#import "SGNKeychainUtil.h"

#define DHRS1_LENGTH 8
#define DHRS2_LENGTH 8
#define DHAUX_LENGTH 8
#define DHPBX_LENGTH 8
#define IV_LENGTH 16

@interface ZRTPResponder ()

@property (strong, nonatomic) HelloPacket* localHello;
@property (strong, nonatomic) HelloPacket* foreignHello;
@property (strong, nonatomic) CommitPacket* foreignCommit;
@property (strong, nonatomic) DHPacket* localDH;
@property (strong, nonatomic) DHPacket* foreignDH;
@property (strong, nonatomic) NSArray* allowedKeyAgreementProtocols;
@property (strong, nonatomic) id<KeyAgreementParticipant> keyAgreementParticipant;
@property (strong, nonatomic) HashChain* hashChain;
@property (strong, nonatomic) MasterSecret* masterSecret;
@property (strong, nonatomic) NSData* confirmIV;
@property (strong, nonatomic) DHPacketSharedSecretHashes* dhSharedSecretHashes;
@property (strong, nonatomic) id<OccurrenceLogger> badPacketLogger;
@property (nonatomic) PacketExpectation packetExpectation;
@property (strong, nonatomic) CallController* callController;

@end

@implementation ZRTPResponder

- (instancetype)initWithCallController:(CallController*)callController {
    if (self = [super init]) {
        require(callController != nil);
        
        self.confirmIV                    = [CryptoTools generateSecureRandomData:IV_LENGTH];
        self.dhSharedSecretHashes         = [DHPacketSharedSecretHashes randomized];
        self.allowedKeyAgreementProtocols = Environment.getCurrent.keyAgreementProtocolsInDescendingPriority;
        self.hashChain                    = [[HashChain alloc] initWithSecureGeneratedData];
        self.badPacketLogger              = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"Bad Packet"];
        self.localHello                   = [HelloPacket helloPacketWithDefaultsAndHashChain:self.hashChain
                                                                                      andZid:[SGNKeychainUtil zid]
                                                                    andKeyAgreementProtocols:self.allowedKeyAgreementProtocols];
        self.packetExpectation            = EXPECTING_HELLO;
        self.callController               = callController;
    }
    
    return self;
}

- (HandshakePacket*)initialPacket {
    [self.callController advanceCallProgressTo:CallProgressTypeSecuring];

    return [self.localHello embeddedIntoHandshakePacket];
}

- (bool)hasHandshakeFinishedSuccessfully {
    return self.packetExpectation == EXPECTING_NOTHING;
}

- (HandshakePacket*)handlePacket:(HandshakePacket*)packet {
    @try {
        if      (self.packetExpectation == EXPECTING_NOTHING){     return nil;}
        else if (self.packetExpectation == EXPECTING_HELLO){       return [self handleHello:packet];}
        else if (self.packetExpectation == EXPECTING_COMMIT){      return [self handleCommit:packet];}
        else if (self.packetExpectation == EXPECTING_DH){          return [self handleDH:packet];}
        else if (self.packetExpectation == EXPECTING_CONFIRM)    { return [self handleConfirmTwo:packet];}
        else {return nil;}
    } @catch (SecurityFailure* ex) {
        [self.callController terminateWithReason:CallTerminationTypeHandshakeFailed withFailureInfo:ex andRelatedInfo:packet];
        return nil;
    } @catch (OperationFailed* ex) {
        [self.badPacketLogger markOccurrence:ex];
        return nil;
    }
}

- (HandshakePacket*)handleHello:(HandshakePacket*)packet {
    self.foreignHello = [packet parsedAsHello];
    
    self.packetExpectation = EXPECTING_COMMIT;
    
    return [[[HelloAckPacket alloc] init] embeddedIntoHandshakePacket];
}


- (HandshakePacket*)handleCommit:(HandshakePacket*)packet {
    CommitPacket* cp = [packet parsedAsCommitPacket];
    [self.foreignHello verifyMacWithHashChainH2:[cp h2]];
    
    self.foreignCommit = cp;
    
    self.keyAgreementParticipant = [self retrieveKeyAgreementParticipant];
    
    self.localDH = [DHPacket dh1PacketWithHashChain:self.hashChain
                              andSharedSecretHashes:self.dhSharedSecretHashes
                                       andKeyAgreer:self.keyAgreementParticipant];
    
    self.packetExpectation = EXPECTING_DH;
    
    return [self.localDH embeddedIntoHandshakePacket];
}

- (MasterSecret*)getMasterSecret {
    requireState(self.hasHandshakeFinishedSuccessfully);
    return self.masterSecret;
}

- (HandshakePacket*)handleDH:(HandshakePacket*)packet {
    self.foreignDH = [packet parsedAsDH2];
    
    [self.foreignCommit verifyMacWithHashChainH1:[self.foreignDH hashChainH1]];
    [self.foreignCommit verifyCommitmentAgainstHello:self.localHello
                                          andDHPart2:self.foreignDH];
    
    NSData* dhResult = [self.keyAgreementParticipant calculateKeyAgreementAgainstRemotePublicKey:[self.foreignDH publicKeyData]];
    
    self.masterSecret = [MasterSecret masterSecretFromDHResult:dhResult
                                             andInitiatorHello:self.foreignHello
                                             andResponderHello:self.localHello
                                                     andCommit:self.foreignCommit
                                                    andDhPart1:self.localDH
                                                    andDhPart2:self.foreignDH];
    
    self.packetExpectation = EXPECTING_CONFIRM;
    
    ConfirmPacket* confirm2Packet = [ConfirmPacket confirm1PacketWithHashChain:self.hashChain
                                                                     andMacKey:[self.masterSecret responderMacKey]
                                                                  andCipherKey:[self.masterSecret responderZRTPKey]
                                                                         andIV:self.confirmIV];
    
    return [confirm2Packet embeddedIntoHandshakePacket];
}


- (HandshakePacket*)handleConfirmTwo:(HandshakePacket*)packet {
    ConfirmPacket* confirmPacket = [packet parsedAsConfirm2AuthenticatedWithMacKey:[self.masterSecret initiatorMacKey]
                                                                      andCipherKey:[self.masterSecret initiatorZRTPKey]];
    
    [self.foreignDH verifyMacWithHashChainH0:[confirmPacket hashChainH0]];
    
    self.packetExpectation = EXPECTING_NOTHING;
    
    if ([Environment hasEnabledTestingOrLegacyOption:ENVIRONMENT_TESTING_OPTION_LOSE_CONF_ACK_ON_PURPOSE]) {
        return nil;
    }
    
    return [[[ConfirmAckPacket alloc] init] embeddedIntoHandshakePacket];
}

- (bool)isAuthenticatedAudioDataImplyingConf2Ack:(id)packet {
    return false; // responder doesn't expect to receive Conf2Ack
}

- (id<KeyAgreementParticipant>)retrieveKeyAgreementParticipant {
    id<KeyAgreementProtocol> matchingKeyAgreeProtocol = [self.allowedKeyAgreementProtocols firstMatchingElseNil:^int(id<KeyAgreementProtocol> a) {
        return [[self.foreignCommit agreementSpecId] isEqualToData:a.getId];
    }];
    
    checkOperation(matchingKeyAgreeProtocol != nil);
    return [matchingKeyAgreeProtocol generateParticipantWithNewKeys];
}

- (SRTPSocket*)useKeysToSecureRTPSocket:(RTPSocket*)rtpSocket {
    requireState(self.hasHandshakeFinishedSuccessfully);
    return [[SRTPSocket alloc] initOverRTP:rtpSocket
                      andIncomingCipherKey:[self.masterSecret initiatorSrtpKey]
                         andIncomingMacKey:[self.masterSecret initiatorMacKey]
                           andIncomingSalt:[self.masterSecret initiatorSrtpSalt]
                      andOutgoingCipherKey:[self.masterSecret responderSrtpKey]
                         andOutgoingMacKey:[self.masterSecret responderMacKey]
                           andOutgoingSalt:[self.masterSecret responderSrtpSalt]];
}

@end

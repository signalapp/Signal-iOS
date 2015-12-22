#import "CommitPacket.h"
#import "ConfirmAckPacket.h"
#import "ConfirmPacket.h"
#import "HelloAckPacket.h"
#import "MasterSecret.h"
#import "SignalKeyingStorage.h"
#import "ZrtpResponder.h"

#define DHRS1_LENGTH 8
#define DHRS2_LENGTH 8
#define DHAUX_LENGTH 8
#define DHPBX_LENGTH 8
#define IV_LENGTH 16

@implementation ZrtpResponder

+ (ZrtpResponder *)zrtpResponderWithCallController:(CallController *)callController {
    ows_require(callController != nil);

    ZrtpResponder *s = [ZrtpResponder new];

    s->confirmIv                    = [CryptoTools generateSecureRandomData:IV_LENGTH];
    s->dhSharedSecretHashes         = [DhPacketSharedSecretHashes dhPacketSharedSecretHashesRandomized];
    s->allowedKeyAgreementProtocols = Environment.getCurrent.keyAgreementProtocolsInDescendingPriority;
    s->hashChain                    = [HashChain hashChainWithSecureGeneratedData];
    s->badPacketLogger              = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"Bad Packet"];

    s->localHello = [HelloPacket helloPacketWithDefaultsAndHashChain:s->hashChain
                                                              andZid:[Zid nullZid]
                                            andKeyAgreementProtocols:s->allowedKeyAgreementProtocols];
    s->packetExpectation = EXPECTING_HELLO;
    s->callController    = callController;
    return s;
}

- (HandshakePacket *)initialPacket {
    [callController advanceCallProgressTo:CallProgressType_Securing];

    return [localHello embeddedIntoHandshakePacket];
}
- (bool)hasHandshakeFinishedSuccessfully {
    return packetExpectation == EXPECTING_NOTHING;
}
- (HandshakePacket *)handlePacket:(HandshakePacket *)packet {
    @try {
        if (packetExpectation == EXPECTING_NOTHING) {
            return nil;
        } else if (packetExpectation == EXPECTING_HELLO) {
            return [self handleHello:packet];
        } else if (packetExpectation == EXPECTING_COMMIT) {
            return [self handleCommit:packet];
        } else if (packetExpectation == EXPECTING_DH) {
            return [self handleDH:packet];
        } else if (packetExpectation == EXPECTING_CONFIRM) {
            return [self handleConfirmTwo:packet];
        } else {
            return nil;
        }
    } @catch (SecurityFailure *ex) {
        [callController terminateWithReason:CallTerminationType_HandshakeFailed
                            withFailureInfo:ex
                             andRelatedInfo:packet];
        return nil;
    } @catch (OperationFailed *ex) {
        [badPacketLogger markOccurrence:ex];
        return nil;
    }
}

- (HandshakePacket *)handleHello:(HandshakePacket *)packet {
    foreignHello = [packet parsedAsHello];

    packetExpectation = EXPECTING_COMMIT;

    return [[HelloAckPacket helloAckPacket] embeddedIntoHandshakePacket];
}


- (HandshakePacket *)handleCommit:(HandshakePacket *)packet {
    CommitPacket *cp = [packet parsedAsCommitPacket];
    [foreignHello verifyMacWithHashChainH2:[cp h2]];

    foreignCommit = cp;

    keyAgreementParticipant = [self retrieveKeyAgreementParticipant];

    localDH = [DhPacket dh1PacketWithHashChain:hashChain
                         andSharedSecretHashes:dhSharedSecretHashes
                                  andKeyAgreer:keyAgreementParticipant];

    packetExpectation = EXPECTING_DH;

    return [localDH embeddedIntoHandshakePacket];
}

- (MasterSecret *)getMasterSecret {
    requireState(self.hasHandshakeFinishedSuccessfully);
    return masterSecret;
}

- (HandshakePacket *)handleDH:(HandshakePacket *)packet {
    foreignDH = [packet parsedAsDh2];

    [foreignCommit verifyMacWithHashChainH1:[foreignDH hashChainH1]];
    [foreignCommit verifyCommitmentAgainstHello:localHello andDhPart2:foreignDH];

    NSData *dhResult = [keyAgreementParticipant calculateKeyAgreementAgainstRemotePublicKey:[foreignDH publicKeyData]];

    masterSecret = [MasterSecret masterSecretFromDhResult:dhResult
                                        andInitiatorHello:foreignHello
                                        andResponderHello:localHello
                                                andCommit:foreignCommit
                                               andDhPart1:localDH
                                               andDhPart2:foreignDH];

    packetExpectation = EXPECTING_CONFIRM;

    ConfirmPacket *confirm2Packet = [ConfirmPacket confirm1PacketWithHashChain:hashChain
                                                                     andMacKey:[masterSecret responderMacKey]
                                                                  andCipherKey:[masterSecret responderZrtpKey]
                                                                         andIv:confirmIv];

    return [confirm2Packet embeddedIntoHandshakePacket];
}


- (HandshakePacket *)handleConfirmTwo:(HandshakePacket *)packet {
    ConfirmPacket *confirmPacket = [packet parsedAsConfirm2AuthenticatedWithMacKey:[masterSecret initiatorMacKey]
                                                                      andCipherKey:[masterSecret initiatorZrtpKey]];

    [foreignDH verifyMacWithHashChainH0:[confirmPacket hashChainH0]];

    packetExpectation = EXPECTING_NOTHING;

    if ([Environment hasEnabledTestingOrLegacyOption:ENVIRONMENT_TESTING_OPTION_LOSE_CONF_ACK_ON_PURPOSE]) {
        return nil;
    }

    return [[ConfirmAckPacket confirmAckPacket] embeddedIntoHandshakePacket];
}

- (bool)isAuthenticatedAudioDataImplyingConf2Ack:(id)packet {
    return false; // responder doesn't expect to receive Conf2Ack
}

- (id<KeyAgreementParticipant>)retrieveKeyAgreementParticipant {
    id<KeyAgreementProtocol> matchingKeyAgreeProtocol =
        [allowedKeyAgreementProtocols firstMatchingElseNil:^int(id<KeyAgreementProtocol> a) {
          return [[foreignCommit agreementSpecId] isEqualToData:a.getId];
        }];

    checkOperation(matchingKeyAgreeProtocol != nil);
    return [matchingKeyAgreeProtocol generateParticipantWithNewKeys];
}

- (SrtpSocket *)useKeysToSecureRtpSocket:(RtpSocket *)rtpSocket {
    requireState(self.hasHandshakeFinishedSuccessfully);
    return [SrtpSocket srtpSocketOverRtp:rtpSocket
                    andIncomingCipherKey:[masterSecret initiatorSrtpKey]
                       andIncomingMacKey:[masterSecret initiatorMacKey]
                         andIncomingSalt:[masterSecret initiatorSrtpSalt]
                    andOutgoingCipherKey:[masterSecret responderSrtpKey]
                       andOutgoingMacKey:[masterSecret responderMacKey]
                         andOutgoingSalt:[masterSecret responderSrtpSalt]];
}

@end

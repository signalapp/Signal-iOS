#import "ConfirmPacket.h"
#import "MasterSecret.h"
#import "SignalKeyingStorage.h"
#import "ZrtpInitiator.h"

#define DHRS1_LENGTH 8
#define DHRS2_LENGTH 8
#define DHAUX_LENGTH 8
#define DHPBX_LENGTH 8
#define IV_LENGTH 16

@implementation ZrtpInitiator

+ (ZrtpInitiator *)zrtpInitiatorWithCallController:(CallController *)callController {
    ows_require(callController != nil);

    ZrtpInitiator *s = [ZrtpInitiator new];

    s->allowedKeyAgreementProtocols = Environment.getCurrent.keyAgreementProtocolsInDescendingPriority;
    s->dhSharedSecretHashes         = [DhPacketSharedSecretHashes dhPacketSharedSecretHashesRandomized];
    s->zid                          = [Zid nullZid];
    s->confirmIv                    = [CryptoTools generateSecureRandomData:IV_LENGTH];
    s->hashChain                    = [HashChain hashChainWithSecureGeneratedData];
    s->badPacketLogger              = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"Bad Packet"];
    s->packetExpectation            = EXPECTING_HELLO;
    s->callController               = callController;

    return s;
}

- (MasterSecret *)getMasterSecret {
    requireState(self.hasHandshakeFinishedSuccessfully);
    return masterSecret;
}

- (HandshakePacket *)initialPacket {
    return nil;
}
- (bool)hasHandshakeFinishedSuccessfully {
    return packetExpectation == EXPECTING_NOTHING;
}
- (HandshakePacket *)handlePacket:(HandshakePacket *)packet {
    @try {
        if (packetExpectation == EXPECTING_NOTHING)
            return nil;
        else if (packetExpectation == EXPECTING_HELLO)
            return [self handleHello:packet];
        else if (packetExpectation == EXPECTING_HELLO_ACK)
            return [self handleHelloAck:packet];
        else if (packetExpectation == EXPECTING_DH)
            return [self handleDH:packet];
        else if (packetExpectation == EXPECTING_CONFIRM)
            return [self handleConfirmOne:packet];
        else if (packetExpectation == EXPECTING_CONFIRM_ACK)
            return [self handleConfirmAck:packet];
        else
            return nil;

    } @catch (SecurityFailure *exception) {
        [callController terminateWithReason:CallTerminationType_HandshakeFailed
                            withFailureInfo:exception
                             andRelatedInfo:packet];
        return nil;
    } @catch (OperationFailed *ex) {
        [badPacketLogger markOccurrence:ex];
        return nil;
    }
}

- (HandshakePacket *)handleHello:(HandshakePacket *)packet {
    foreignHello = [packet parsedAsHello];

    [callController advanceCallProgressTo:CallProgressType_Securing];

    keyAgreementParticipant = [self retrieveKeyAgreementParticpant];

    localHello = [HelloPacket helloPacketWithDefaultsAndHashChain:hashChain
                                                           andZid:zid
                                         andKeyAgreementProtocols:allowedKeyAgreementProtocols];

    packetExpectation = EXPECTING_HELLO_ACK;

    return [localHello embeddedIntoHandshakePacket];
}

- (HandshakePacket *)handleHelloAck:(HandshakePacket *)packet {
    [packet parsedAsHelloAck];

    [self retrieveKeyAgreementParticpant];

    localDH = [DhPacket dh2PacketWithHashChain:hashChain
                         andSharedSecretHashes:dhSharedSecretHashes
                                  andKeyAgreer:keyAgreementParticipant];

    commitPacket = [CommitPacket commitPacketWithDefaultSpecsAndKeyAgreementProtocol:keyAgreementParticipant.getProtocol
                                                                        andHashChain:hashChain
                                                                              andZid:zid
                                                                andCommitmentToHello:foreignHello
                                                                          andDhPart2:localDH];

    packetExpectation = EXPECTING_DH;

    return [commitPacket embeddedIntoHandshakePacket];
}

- (HandshakePacket *)handleDH:(HandshakePacket *)packet {
    foreignDH = [packet parsedAsDh1];

    [foreignHello verifyMacWithHashChainH2:[[foreignDH hashChainH1] hashWithSha256]];

    NSData *dhResult = [keyAgreementParticipant calculateKeyAgreementAgainstRemotePublicKey:[foreignDH publicKeyData]];

    masterSecret = [MasterSecret masterSecretFromDhResult:dhResult
                                        andInitiatorHello:localHello
                                        andResponderHello:foreignHello
                                                andCommit:commitPacket
                                               andDhPart1:foreignDH
                                               andDhPart2:localDH];

    packetExpectation = EXPECTING_CONFIRM;
    return [localDH embeddedIntoHandshakePacket];
}

- (HandshakePacket *)handleConfirmOne:(HandshakePacket *)packet {
    ConfirmPacket *confirmPacket = [packet parsedAsConfirm1AuthenticatedWithMacKey:[masterSecret responderMacKey]
                                                                      andCipherKey:[masterSecret responderZrtpKey]];

    NSData *preimage = [confirmPacket hashChainH0];
    [foreignDH verifyMacWithHashChainH0:preimage];

    packetExpectation             = EXPECTING_CONFIRM_ACK;
    ConfirmPacket *confirm2Packet = [ConfirmPacket confirm2PacketWithHashChain:hashChain
                                                                     andMacKey:[masterSecret initiatorMacKey]
                                                                  andCipherKey:[masterSecret initiatorZrtpKey]
                                                                         andIv:confirmIv];
    return [confirm2Packet embeddedIntoHandshakePacket];
}

- (HandshakePacket *)handleConfirmAck:(HandshakePacket *)packet {
    [packet parsedAsConfAck];

    packetExpectation = EXPECTING_NOTHING;
    return nil;
}

- (bool)isAuthenticatedAudioDataImplyingConf2Ack:(id)packet {
    if (packetExpectation != EXPECTING_CONFIRM_ACK)
        return false;
    if (![packet isKindOfClass:RtpPacket.class])
        return false;

    @try {
        SrtpStream *incomingContext = [SrtpStream srtpStreamWithCipherKey:[masterSecret responderSrtpKey]
                                                                andMacKey:[masterSecret responderMacKey]
                                                          andCipherIvSalt:[masterSecret responderSrtpSalt]];
        [incomingContext verifyAuthenticationAndDecryptSecuredRtpPacket:packet];
        return true;
    } @catch (OperationFailed *ex) {
        return false;
    }
}

- (id<KeyAgreementParticipant>)retrieveKeyAgreementParticpant {
    NSArray *idsOfProtocolsAllowedByPeer = [foreignHello agreeIdsIncludingImplied];

    id<KeyAgreementProtocol> bestCommonKeyAgreementProtocol =
        [allowedKeyAgreementProtocols firstMatchingElseNil:^int(id<KeyAgreementProtocol> locallyAllowedProtocol) {
          return [idsOfProtocolsAllowedByPeer containsObject:locallyAllowedProtocol.getId];
        }];

    // Note: should never fail to find a common protocol because DH3k support is required and implied
    checkOperation(bestCommonKeyAgreementProtocol != nil);

    return [bestCommonKeyAgreementProtocol generateParticipantWithNewKeys];
}

- (SrtpSocket *)useKeysToSecureRtpSocket:(RtpSocket *)rtpSocket {
    requireState(self.hasHandshakeFinishedSuccessfully);
    return [SrtpSocket srtpSocketOverRtp:rtpSocket
                    andIncomingCipherKey:[masterSecret responderSrtpKey]
                       andIncomingMacKey:[masterSecret responderMacKey]
                         andIncomingSalt:[masterSecret responderSrtpSalt]
                    andOutgoingCipherKey:[masterSecret initiatorSrtpKey]
                       andOutgoingMacKey:[masterSecret initiatorMacKey]
                         andOutgoingSalt:[masterSecret initiatorSrtpSalt]];
}

@end

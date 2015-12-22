#import "DhPacketSharedSecretHashes.h"
#import "Constraints.h"
#import "CryptoTools.h"

@implementation DhPacketSharedSecretHashes

@synthesize aux, pbx, rs1, rs2;

+(DhPacketSharedSecretHashes*) dhPacketSharedSecretHashesRandomized {
    return [DhPacketSharedSecretHashes dhPacketSharedSecretHashesWithRs1:[CryptoTools generateSecureRandomData:DH_RS1_LENGTH]
                                                                  andRs2:[CryptoTools generateSecureRandomData:DH_RS2_LENGTH]
                                                                  andAux:[CryptoTools generateSecureRandomData:DH_AUX_LENGTH]
                                                                  andPbx:[CryptoTools generateSecureRandomData:DH_PBX_LENGTH]];
}

+(DhPacketSharedSecretHashes*) dhPacketSharedSecretHashesWithRs1:(NSData*)rs1
                                                          andRs2:(NSData*)rs2
                                                          andAux:(NSData*)aux
                                                          andPbx:(NSData*)pbx {
    ows_require(rs1 != nil);
    ows_require(rs2 != nil);
    ows_require(aux != nil);
    ows_require(pbx != nil);
    
    ows_require(rs1.length == DH_RS1_LENGTH);
    ows_require(rs2.length == DH_RS2_LENGTH);
    ows_require(aux.length == DH_AUX_LENGTH);
    ows_require(pbx.length == DH_PBX_LENGTH);
    
    DhPacketSharedSecretHashes* h = [DhPacketSharedSecretHashes new];
    h->rs1 = rs1;
    h->rs2 = rs2;
    h->aux = aux;
    h->pbx = pbx;
    return h;
}

@end

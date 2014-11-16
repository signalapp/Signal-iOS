#import "DHPacketSharedSecretHashes.h"
#import "Constraints.h"
#import "CryptoTools.h"

@interface DHPacketSharedSecretHashes ()

@property (strong, readwrite, nonatomic) NSData* rs1;
@property (strong, readwrite, nonatomic) NSData* rs2;
@property (strong, readwrite, nonatomic) NSData* aux;
@property (strong, readwrite, nonatomic) NSData* pbx;

@end

@implementation DHPacketSharedSecretHashes

+ (DHPacketSharedSecretHashes*)randomized {
    return [[DHPacketSharedSecretHashes alloc] initWithRs1:[CryptoTools generateSecureRandomData:DH_RS1_LENGTH]
                                                    andRs2:[CryptoTools generateSecureRandomData:DH_RS2_LENGTH]
                                                    andAux:[CryptoTools generateSecureRandomData:DH_AUX_LENGTH]
                                                    andPbx:[CryptoTools generateSecureRandomData:DH_PBX_LENGTH]];
}

- (instancetype)initWithRs1:(NSData*)rs1
                     andRs2:(NSData*)rs2
                     andAux:(NSData*)aux
                     andPbx:(NSData*)pbx {
    if (self = [super init]) {
        require(rs1 != nil);
        require(rs2 != nil);
        require(aux != nil);
        require(pbx != nil);
        
        require(rs1.length == DH_RS1_LENGTH);
        require(rs2.length == DH_RS2_LENGTH);
        require(aux.length == DH_AUX_LENGTH);
        require(pbx.length == DH_PBX_LENGTH);
        
        self.rs1 = rs1;
        self.rs2 = rs2;
        self.aux = aux;
        self.pbx = pbx;
    }
    
    return self;
}

@end

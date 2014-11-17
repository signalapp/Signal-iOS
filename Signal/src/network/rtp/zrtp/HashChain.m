#import "CryptoTools.h"
#import "NSData+CryptoTools.h"
#import "Constraints.h"
#import "HashChain.h"

@interface HashChain ()

@property (strong, readwrite, nonatomic) NSData* h0;
@property (strong, readwrite, nonatomic) NSData* h1;
@property (strong, readwrite, nonatomic) NSData* h2;
@property (strong, readwrite, nonatomic) NSData* h3;

@end

@implementation HashChain

- (instancetype)initWithSeed:(NSData*)seed {
    if (self = [super init]) {
        require(seed != nil);
        require(seed.length == HASH_CHAIN_ITEM_LENGTH);
        
        self.h0 = seed;
        self.h1 = [self.h0 hashWithSHA256];
        self.h2 = [self.h1 hashWithSHA256];
        self.h3 = [self.h2 hashWithSHA256];
    }
    
    return self;
}

- (instancetype)initWithSecureGeneratedData {
    return [self initWithSeed:[CryptoTools generateSecureRandomData:HASH_CHAIN_ITEM_LENGTH]];
}

@end

#import "EVPKeyAgreement.h"
#import "Util.h"
#import <openssl/bn.h>
#import <openssl/dh.h>
#import <openssl/ec.h>
#import <openssl/pem.h>

#define checkEVPOperationResult(expr) checkSecurityOperation((expr) == 1, @"An elliptic curve operation didn't succeed.")
#define checkEVPNotNull(expr, desc) checkSecurityOperation((expr) != NULL, desc)

#define EC25_COORDINATE_LENGTH 32
#define NAMED_ELLIPTIC_CURVE NID_X9_62_prime256v1

@interface EVPKeyAgreement () {
    EVP_PKEY* params;
    EVP_PKEY* pkey;
}

typedef NS_ENUM(NSInteger, KeyAgreementType) {
    KeyAgreementTypeDH = EVP_PKEY_DH,
    KeyAgreementTypeECDH = EVP_PKEY_EC
};

@property (nonatomic) KeyAgreementType keyAgreementType;

@end

@implementation EVPKeyAgreement

#pragma mark Constructors / Initialization

+ (instancetype)evpDH3KKeyAgreementWithModulus:(NSData*)modulus andGenerator:(NSData*)generator {
    EVPKeyAgreement* evpKeyAgreement = [[EVPKeyAgreement alloc] initWithKeyType:KeyAgreementTypeDH ];
    assert(nil != modulus);
    assert(nil != generator);
    
    [evpKeyAgreement generateDHParametersWithModulus:modulus andGenerator:generator];
    [evpKeyAgreement generateKeyPair];
    return evpKeyAgreement;
}

+ (instancetype)evpEC25KeyAgreement {
    EVPKeyAgreement* evpKeyAgreement = [[EVPKeyAgreement alloc] initWithKeyType:KeyAgreementTypeECDH];
    [evpKeyAgreement generateEc25Parameters];
    [evpKeyAgreement generateKeyPair];
    return evpKeyAgreement;
}

- (instancetype)initWithKeyType:(KeyAgreementType)keyType {
    self = [super init];
	
    if (self) {
        self.keyAgreementType = keyType;
    }
    
    return self;
}

- (void)dealloc {
    [self freeKey:params];
    [self freeKey:pkey];
}

- (EVP_PKEY_CTX*)createParameterContext {
    EVP_PKEY_CTX* ctx;
    ctx = EVP_PKEY_CTX_new_id(self.keyAgreementType, NULL);
    checkEVPNotNull(ctx , @"pctx_new_id");
    
    checkEVPOperationResult(EVP_PKEY_paramgen_init(ctx));
    
    return ctx;
}

#pragma mark Parameter/Key Generation
- (void)generateDHParametersWithModulus:(NSData*)modulus andGenerator:(NSData*)generator {
    
    EVP_PKEY_CTX* pctx = [self createParameterContext];
    DH* dh = DH_new();
    
    @try{
        checkEVPNotNull(dh, @"dh_new");
        
        dh->p = [self generateBignumberFor:modulus];
        dh->g = [self generateBignumberFor:generator];
        
        if ((dh->p == NULL) || (dh->g == NULL))
        {
            [self reportError:@"DH Parameters uninitialized"];
        }
        
        [self createNewEVPKeyFreePreviousIfNessesary:&params];
        EVP_PKEY_set1_DH(params, dh);
        
    } @finally {
        DH_free(dh);
        EVP_PKEY_CTX_free(pctx);
    }
}

- (void) generateEc25Parameters {
    EVP_PKEY_CTX* pctx = [self createParameterContext];
    
    checkEVPOperationResult(EVP_PKEY_CTX_set_ec_paramgen_curve_nid(pctx, NAMED_ELLIPTIC_CURVE));
    
    checkEVPOperationResult(EVP_PKEY_paramgen(pctx, &params));
    
    EVP_PKEY_CTX_free(pctx);
}


- (void)generateKeyPair {
    checkEVPNotNull(params, @"parameters uninitialized");
    
    EVP_PKEY_CTX* kctx = NULL;
    @try {
        kctx = EVP_PKEY_CTX_new(params, NULL);
        checkEVPNotNull(kctx, @"key_ctx");
        
        checkEVPOperationResult(EVP_PKEY_keygen_init(kctx));
        
        checkEVPOperationResult(EVP_PKEY_keygen(kctx, &pkey));
    } @finally {
        if (kctx != NULL) EVP_PKEY_CTX_free(kctx);
    }
}


- (NSData*)getSharedSecretForRemotePublicKey:(NSData*)publicKey {
    EVP_PKEY* peerkey = [self deserializePublicKey:publicKey];
    EVP_PKEY_CTX* ctx = EVP_PKEY_CTX_new(pkey, NULL);
    checkEVPNotNull(ctx, @"ctx_new");
    
    checkEVPOperationResult(EVP_PKEY_derive_init(ctx));
    checkEVPOperationResult(EVP_PKEY_derive_set_peer(ctx, peerkey));
    
    size_t secret_len;
    checkEVPOperationResult(EVP_PKEY_derive(ctx, NULL, &secret_len));
    
    unsigned char* secret = OPENSSL_malloc(secret_len);
    checkEVPNotNull(secret, @"OPENSSL_malloc");
    
    checkEVPOperationResult(EVP_PKEY_derive(ctx, secret, &secret_len));
    
    NSData* secretData = [NSData dataWithBytes:secret length:secret_len];
    
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(peerkey);
    OPENSSL_free(secret);
    
    return secretData;
}

#pragma mark Public Key Serialization

- (NSData*)getPublicKey {
    switch (self.keyAgreementType) {
        case KeyAgreementTypeDH:
            return [self serializeDhPublicKey:pkey];
        case KeyAgreementTypeECDH:
            return [self serializeEcPublicKey:pkey];
        default:
            [self reportError:@"Undefined KeyType"];
    }
}

- (NSData*)serializeDhPublicKey:(EVP_PKEY*)evkey {
    DH* dh = NULL;
    unsigned char* buf = NULL;
    @try {
        dh = EVP_PKEY_get1_DH(evkey);
        checkEVPNotNull(dh, @"EVP_PKEY_get1_DH");
        
        int publicKeySize = BN_num_bytes(dh->pub_key);
        NSMutableData* publicKeyBuffer = [NSMutableData dataWithLength:(NSUInteger)publicKeySize];
        
        int wroteLength = BN_bn2bin(dh->pub_key, publicKeyBuffer.mutableBytes);
        checkSecurityOperation(wroteLength == (long long)publicKeyBuffer.length, @"BN_bn2bin");
        
        return publicKeyBuffer;
    } @finally {
        if (dh != NULL) DH_free(dh);
        if (buf != NULL) OPENSSL_free(buf);
    }
}


- (NSData*)serializeEcPublicKey:(EVP_PKEY*)evkey {
    require(evkey != NULL);
    
    EC_KEY* ec_key = NULL;
    @try {
        ec_key = EVP_PKEY_get1_EC_KEY(evkey);
        checkEVPNotNull(ec_key, @"EVP_PKEY_get1_EC_KEY");
        
        const EC_POINT* ec_pub = EC_KEY_get0_public_key(ec_key);
        checkEVPNotNull(ec_pub, @"EC_KEY_get0_public_key");

        const EC_GROUP* ec_group = EC_KEY_get0_group(ec_key);
        checkEVPNotNull(ec_group, @"EC_KEY_get0_group");
        
        return [self packEcCoordinatesFromEcPoint:ec_pub withEcGroup:ec_group];
    } @finally {
        EC_KEY_free(ec_key);
    }
}

- (EVP_PKEY*)deserializePublicKey:(NSData*)buf {
    switch (self.keyAgreementType) {
        case KeyAgreementTypeDH:
            return [self deserializeDhPublicKey:buf];
        case KeyAgreementTypeECDH:
            return [self deserializeEcPublicKey:buf];
        default:
            [self reportError:@"Undefined KeyType"];
    }
}

- (EVP_PKEY*)deserializeDhPublicKey:(NSData*)buf {
    EVP_PKEY* evpk = NULL;
    DH* dh = NULL;
    BIGNUM* bn = NULL;
    @try {
        evpk = EVP_PKEY_new();
        checkEVPNotNull(evpk, @"EVP_PKEY_new");
        
        dh = DH_new();
        checkEVPNotNull(dh, @"DH_new");
        
        bn = BN_bin2bn(buf.bytes, [NumberUtil assertConvertNSUIntegerToInt:buf.length], NULL);
        checkEVPNotNull(bn, @"BN_bin2bn");

        dh->pub_key = bn;
        checkEVPOperationResult(EVP_PKEY_assign_DH(evpk, dh));

        // Return without cleaning up the result
        EVP_PKEY* result = evpk;
        evpk = NULL;
        dh = NULL;
        bn = NULL;
        return result;
    } @finally {
        if (evpk != NULL) EVP_PKEY_free(evpk);
        if (dh != NULL) DH_free(dh);
        if (bn != NULL) BN_free(bn);
    }
}


- (EVP_PKEY*)deserializeEcPublicKey:(NSData*)buf {
    EC_KEY* key = NULL;
    EC_POINT* publicKeyPoint = NULL;
    EVP_PKEY* publicKey = NULL;
    @try {
        key = EC_KEY_new_by_curve_name(NAMED_ELLIPTIC_CURVE);
        checkSecurityOperation(key != NULL, @"EC_KEY_new_by_curve_name");
        
        const EC_GROUP* group = EC_KEY_get0_group(key);
        checkSecurityOperation(group != NULL, @"EC_KEY_get0_group");
        
        publicKeyPoint = EC_POINT_new(group);
        checkSecurityOperation(publicKeyPoint != NULL, @"EC_POINT_new");
        
        [self unpackEcCoordinatesFromBuffer:buf
                                  toEcPoint:publicKeyPoint
                                withEcGroup:group];
        
        publicKey = EVP_PKEY_new();
        checkSecurityOperation(publicKey != NULL, @"EVP_PKEY_new");
        
        checkEVPOperationResult(EC_KEY_set_public_key(key, publicKeyPoint));
        
        checkEVPOperationResult(EVP_PKEY_assign_EC_KEY(publicKey, key));
        
        // Return without cleaning up the result
        EVP_PKEY* result = publicKey;
        publicKey = NULL;
        key = NULL;
        publicKeyPoint = NULL;
        return result;
    } @finally {
        if (key != NULL) EC_KEY_free(key);
        if (publicKeyPoint != NULL) EC_POINT_free(publicKeyPoint);
        if (publicKey != NULL) EVP_PKEY_free(publicKey);
    }
}

- (NSData*)packEcCoordinatesFromEcPoint:(const EC_POINT*)ec_point withEcGroup:(const EC_GROUP*)ec_group {
    BIGNUM *x = NULL;
    BIGNUM *y = NULL;
    @try {
        x = BN_new();
        y = BN_new();
        checkSecurityOperation(x != NULL && y != NULL, @"BN_new");
        
        checkEVPOperationResult(EC_POINT_get_affine_coordinates_GFp(ec_group, ec_point, x, y, NULL));
        
        int len_x = BN_num_bytes(x);
        int len_y = BN_num_bytes(y);
        checkSecurityOperation(len_x >= 0 && len_x <= EC25_COORDINATE_LENGTH, @"BN_num_bytes(x)");
        checkSecurityOperation(len_y >= 0 && len_y <= EC25_COORDINATE_LENGTH, @"BN_num_bytes(y)");
        int unused_x = EC25_COORDINATE_LENGTH - len_x;
        int unused_y = EC25_COORDINATE_LENGTH - len_y;
        
        NSMutableData* data = [NSMutableData dataWithLength:EC25_COORDINATE_LENGTH*2];
        
        // We offset the writes to keep things constant sized.
        // Leading zeroes have no effect on the deserialization because BN_bn2bin outputs the bytes in big-endian order.
        int wrote_x = BN_bn2bin(x, data.mutableBytes + unused_x);
        int wrote_y = BN_bn2bin(y, data.mutableBytes + EC25_COORDINATE_LENGTH + unused_y);
        checkSecurityOperation(wrote_x == len_x && wrote_y == len_y, @"BN_bn2bin");
        
        return data;
    } @finally {
        if (x != NULL) BN_free(x);
        if (y != NULL) BN_free(y);
    }
}

- (void)unpackEcCoordinatesFromBuffer:(NSData*)buffer
                            toEcPoint:(EC_POINT*)ecp
                          withEcGroup:(const EC_GROUP*)ecg {
    
    checkOperation(buffer.length == 2*EC25_COORDINATE_LENGTH);
    
    BIGNUM* x = NULL;
    BIGNUM* y = NULL;
    @try {
        const unsigned char* bytes = buffer.bytes;
        x = BN_bin2bn(bytes,                          EC25_COORDINATE_LENGTH, NULL);
        y = BN_bin2bn(bytes + EC25_COORDINATE_LENGTH, EC25_COORDINATE_LENGTH, NULL);
        checkSecurityOperation(x != NULL && y != NULL, @"BN_bin2bn");
        
        checkEVPOperationResult(EC_POINT_set_affine_coordinates_GFp(ecg, ecp, x, y, NULL));
    } @finally {
        if (x != NULL) BN_free(x);
        if (y != NULL) BN_free(y);
    }
}

#pragma mark Helper Functions

- (void)createNewEVPKeyFreePreviousIfNessesary:(EVP_PKEY**)evpKey {
    if (NULL != evpKey) {
        [self freeKey:(*evpKey)];
    }
    (*evpKey) = EVP_PKEY_new();
}

- (void)freeKey:(EVP_PKEY*)evpKey {
    if (NULL != evpKey) {
        EVP_PKEY_free(evpKey);
    }
}

- (BIGNUM*)generateBignumberFor:(NSData*)data {
    assert(data.length <= INT_MAX );
    return BN_bin2bn([data bytes], (int)data.length, NULL);
}

- (void)reportError:(NSString*) errorString {
    [SecurityFailure raise:[NSString stringWithFormat:@"Security related failure: %@ (in %s at line %d)", errorString,__FILE__,__LINE__]];
}

@end

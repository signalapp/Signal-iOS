//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSCountryMetadata : NSObject

@property (nonatomic) NSString *name;
@property (nonatomic) NSString *tld;
@property (nonatomic, nullable) NSString *frontingDomain;
@property (nonatomic) NSString *countryCode;
@property (nonatomic) NSString *localizedCountryName;

+ (OWSCountryMetadata *)countryMetadataForCountryCode:(NSString *)countryCode;

+ (NSArray<OWSCountryMetadata *> *)allCountryMetadatas;

@end

NS_ASSUME_NONNULL_END

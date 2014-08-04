//
//  M2PhoneMetaData.h
//  libPhoneNumber
//
//

#import <Foundation/Foundation.h>

@class NBPhoneNumberDesc, NBNumberFormat;

@interface NBPhoneMetaData : NSObject

// from phonemetadata.pb.js
/*  1 */ @property (nonatomic, strong, readwrite) NBPhoneNumberDesc *generalDesc;
/*  2 */ @property (nonatomic, strong, readwrite) NBPhoneNumberDesc *fixedLine;
/*  3 */ @property (nonatomic, strong, readwrite) NBPhoneNumberDesc *mobile;
/*  4 */ @property (nonatomic, strong, readwrite) NBPhoneNumberDesc *tollFree;
/*  5 */ @property (nonatomic, strong, readwrite) NBPhoneNumberDesc *premiumRate;
/*  6 */ @property (nonatomic, strong, readwrite) NBPhoneNumberDesc *sharedCost;
/*  7 */ @property (nonatomic, strong, readwrite) NBPhoneNumberDesc *personalNumber;
/*  8 */ @property (nonatomic, strong, readwrite) NBPhoneNumberDesc *voip;
/* 21 */ @property (nonatomic, strong, readwrite) NBPhoneNumberDesc *pager;
/* 25 */ @property (nonatomic, strong, readwrite) NBPhoneNumberDesc *uan;
/* 27 */ @property (nonatomic, strong, readwrite) NBPhoneNumberDesc *emergency;
/* 28 */ @property (nonatomic, strong, readwrite) NBPhoneNumberDesc *voicemail;
/* 24 */ @property (nonatomic, strong, readwrite) NBPhoneNumberDesc *noInternationalDialling;
/*  9 */ @property (nonatomic, strong, readwrite) NSString *codeID;
/* 10 */ @property (nonatomic, strong, readwrite) NSNumber *countryCode;
/* 11 */ @property (nonatomic, strong, readwrite) NSString *internationalPrefix;
/* 17 */ @property (nonatomic, strong, readwrite) NSString *preferredInternationalPrefix;
/* 12 */ @property (nonatomic, strong, readwrite) NSString *nationalPrefix;
/* 13 */ @property (nonatomic, strong, readwrite) NSString *preferredExtnPrefix;
/* 15 */ @property (nonatomic, strong, readwrite) NSString *nationalPrefixForParsing;
/* 16 */ @property (nonatomic, strong, readwrite) NSString *nationalPrefixTransformRule;
/* 18 */ @property (nonatomic, assign, readwrite) BOOL sameMobileAndFixedLinePattern;
/* 19 */ @property (nonatomic, strong, readwrite) NSMutableArray *numberFormats;
/* 20 */ @property (nonatomic, strong, readwrite) NSMutableArray *intlNumberFormats;
/* 22 */ @property (nonatomic, assign, readwrite) BOOL mainCountryForCode;
/* 23 */ @property (nonatomic, strong, readwrite) NSString *leadingDigits;
/* 26 */ @property (nonatomic, assign, readwrite) BOOL leadingZeroPossible;

- (void)buildData:(id)data;

@end

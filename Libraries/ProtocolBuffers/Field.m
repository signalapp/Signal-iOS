// Copyright 2008 Cyrus Najmabadi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "Field.h"

#import "CodedOutputStream.h"
#import "MutableField.h"

@interface PBField ()
@property (retain) NSMutableArray* mutableVarintList;
@property (retain) NSMutableArray* mutableFixed32List;
@property (retain) NSMutableArray* mutableFixed64List;
@property (retain) NSMutableArray* mutableLengthDelimitedList;
@property (retain) NSMutableArray* mutableGroupList;
@end

@implementation PBField

static PBField* defaultInstance = nil;

+ (void) initialize {
  if (self == [PBField class]) {
    defaultInstance = [[PBField alloc] init];
  }
}


@synthesize mutableVarintList;
@synthesize mutableFixed32List;
@synthesize mutableFixed64List;
@synthesize mutableLengthDelimitedList;
@synthesize mutableGroupList;


- (void) dealloc {
  self.mutableVarintList = nil;
  self.mutableFixed32List = nil;
  self.mutableFixed64List = nil;
  self.mutableLengthDelimitedList = nil;
  self.mutableGroupList = nil;
}


+ (PBField*) defaultInstance {
  return defaultInstance;
}


- (NSArray*) varintList {
  return mutableVarintList;
}


- (NSArray*) fixed32List {
  return mutableFixed32List;
}


- (NSArray*) fixed64List {
  return mutableFixed64List;
}


- (NSArray*) lengthDelimitedList {
  return mutableLengthDelimitedList;
}


- (NSArray*) groupList {
  return mutableGroupList;
}


- (void) writeTo:(int32_t) fieldNumber
          output:(PBCodedOutputStream*) output {
  for (NSNumber* value in self.varintList) {
    [output writeUInt64:fieldNumber value:value.longLongValue];
  }
  for (NSNumber* value in self.fixed32List) {
    [output writeFixed32:fieldNumber value:value.intValue];
  }
  for (NSNumber* value in self.fixed64List) {
    [output writeFixed64:fieldNumber value:value.longLongValue];
  }
  for (NSData* value in self.lengthDelimitedList) {
    [output writeData:fieldNumber value:value];
  }
  for (PBUnknownFieldSet* value in self.groupList) {
    [output writeUnknownGroup:fieldNumber value:value];
  }
}


- (int32_t) getSerializedSize:(int32_t) fieldNumber {
  int32_t result = 0;
  for (NSNumber* value in self.varintList) {
    result += computeUInt64Size(fieldNumber, value.longLongValue);
  }
  for (NSNumber* value in self.fixed32List) {
    result += computeFixed32Size(fieldNumber, value.intValue);
  }
  for (NSNumber* value in self.fixed64List) {
    result += computeFixed64Size(fieldNumber, value.longLongValue);
  }
  for (NSData* value in self.lengthDelimitedList) {
    result += computeDataSize(fieldNumber, value);
  }
  for (PBUnknownFieldSet* value in self.groupList) {
    result += computeUnknownGroupSize(fieldNumber, value);
  }
  return result;
}


- (void) writeAsMessageSetExtensionTo:(int32_t) fieldNumber
                               output:(PBCodedOutputStream*) output {
  for (NSData* value in self.lengthDelimitedList) {
    [output writeRawMessageSetExtension:fieldNumber value:value];
  }
}


- (int32_t) getSerializedSizeAsMessageSetExtension:(int32_t) fieldNumber {
  int32_t result = 0;
  for (NSData* value in self.lengthDelimitedList) {
    result += computeRawMessageSetExtensionSize(fieldNumber, value);
  }
  return result;
}


@end

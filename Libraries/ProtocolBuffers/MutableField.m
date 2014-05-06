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

#import "MutableField.h"

#import "Field.h"

@interface PBField ()
@property (retain) NSMutableArray* mutableVarintList;
@property (retain) NSMutableArray* mutableFixed32List;
@property (retain) NSMutableArray* mutableFixed64List;
@property (retain) NSMutableArray* mutableLengthDelimitedList;
@property (retain) NSMutableArray* mutableGroupList;
@end


@implementation PBMutableField


+ (PBMutableField*) field {
  return [[PBMutableField alloc] init];
}


- (id) init {
  if ((self = [super init])) {
  }

  return self;
}


- (PBMutableField*) clear {
  self.mutableVarintList = nil;
  self.mutableFixed32List = nil;
  self.mutableFixed64List = nil;
  self.mutableLengthDelimitedList = nil;
  self.mutableGroupList = nil;
  return self;
}


- (PBMutableField*) mergeFromField:(PBField*) other {
  if (other.varintList.count > 0) {
    if (mutableVarintList == nil) {
      self.mutableVarintList = [NSMutableArray array];
    }
    [mutableVarintList addObjectsFromArray:other.varintList];
  }

  if (other.fixed32List.count > 0) {
    if (mutableFixed32List == nil) {
      self.mutableFixed32List = [NSMutableArray array];
    }
    [mutableFixed32List addObjectsFromArray:other.fixed32List];
  }

  if (other.fixed64List.count > 0) {
    if (mutableFixed64List == nil) {
      self.mutableFixed64List = [NSMutableArray array];
    }
    [mutableFixed64List addObjectsFromArray:other.fixed64List];
  }

  if (other.lengthDelimitedList.count > 0) {
    if (mutableLengthDelimitedList == nil) {
      self.mutableLengthDelimitedList = [NSMutableArray array];
    }
    [mutableLengthDelimitedList addObjectsFromArray:other.lengthDelimitedList];
  }

  if (other.groupList.count > 0) {
    if (mutableGroupList == nil) {
      self.mutableGroupList = [NSMutableArray array];
    }
    [mutableGroupList addObjectsFromArray:other.groupList];
  }

  return self;
}


- (PBMutableField*) addVarint:(int64_t) value {
  if (mutableVarintList == nil) {
    self.mutableVarintList = [NSMutableArray array];
  }
  [mutableVarintList addObject:[NSNumber numberWithLongLong:value]];
  return self;
}


- (PBMutableField*) addFixed32:(int32_t) value {
  if (mutableFixed32List == nil) {
    self.mutableFixed32List = [NSMutableArray array];
  }
  [mutableFixed32List addObject:[NSNumber numberWithInt:value]];
  return self;
}


- (PBMutableField*) addFixed64:(int64_t) value {
  if (mutableFixed64List == nil) {
    self.mutableFixed64List = [NSMutableArray array];
  }
  [mutableFixed64List addObject:[NSNumber numberWithLongLong:value]];
  return self;
}


- (PBMutableField*) addLengthDelimited:(NSData*) value {
  if (mutableLengthDelimitedList == nil) {
    self.mutableLengthDelimitedList = [NSMutableArray array];
  }
  [mutableLengthDelimitedList addObject:value];
  return self;
}


- (PBMutableField*) addGroup:(PBUnknownFieldSet*) value {
  if (mutableGroupList == nil) {
    self.mutableGroupList = [NSMutableArray array];
  }
  [mutableGroupList addObject:value];
  return self;
}

@end

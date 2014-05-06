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

typedef enum {
  PBWireFormatVarint = 0,
  PBWireFormatFixed64 = 1,
  PBWireFormatLengthDelimited = 2,
  PBWireFormatStartGroup = 3,
  PBWireFormatEndGroup = 4,
  PBWireFormatFixed32 = 5,

  PBWireFormatTagTypeBits = 3,
  PBWireFormatTagTypeMask = 7 /* = (1 << PBWireFormatTagTypeBits) - 1*/,

  PBWireFormatMessageSetItem = 1,
  PBWireFormatMessageSetTypeId = 2,
  PBWireFormatMessageSetMessage = 3
} PBWireFormat;

int32_t PBWireFormatMakeTag(int32_t fieldNumber, int32_t wireType);
int32_t PBWireFormatGetTagWireType(int32_t tag);
int32_t PBWireFormatGetTagFieldNumber(int32_t tag);

#define PBWireFormatMessageSetItemTag (PBWireFormatMakeTag(PBWireFormatMessageSetItem, PBWireFormatStartGroup))
#define PBWireFormatMessageSetItemEndTag (PBWireFormatMakeTag(PBWireFormatMessageSetItem, PBWireFormatEndGroup))
#define PBWireFormatMessageSetTypeIdTag (PBWireFormatMakeTag(PBWireFormatMessageSetTypeId, PBWireFormatVarint))
#define PBWireFormatMessageSetMessageTag (PBWireFormatMakeTag(PBWireFormatMessageSetMessage, PBWireFormatLengthDelimited))

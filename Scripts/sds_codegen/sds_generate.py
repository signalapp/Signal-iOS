#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
import subprocess 
import datetime
import argparse
import commands
import re
import json
import sds_common
from sds_common import fail
import random

# TODO: We should probably generate a class that knows how to set up 
#       the database.  It would:
#
# * Create all tables (or apply database schema).
# * Register renamed classes.
# [NSKeyedUnarchiver setClass:[OWSUserProfile class] forClassName:[OWSUserProfile collection]];
# [NSKeyedUnarchiver setClass:[OWSDatabaseMigration class] forClassName:[OWSDatabaseMigration collection]];

# We consider any subclass of TSYapDatabaseObject to be a "serializable model".
#
# We treat direct subclasses of TSYapDatabaseObject as "roots" of the model class hierarchy.
# Only root models do deserialization.
BASE_MODEL_CLASS_NAME = 'TSYapDatabaseObject'


# ---- 

global_class_map = {}
global_subclass_map = {}

global global_args
global_args = None

# ---- 


def to_swift_identifer_name(identifer_name):
    return identifer_name[0].lower() + identifer_name[1:]
    
class ParsedClass:
     def __init__(self, json_dict):
         self.name = json_dict.get('name')
         self.super_class_name = json_dict.get('super_class_name')
         self.filepath = sds_common.sds_from_relative_path(json_dict.get('filepath'))
         self.property_map = {}
         for property_dict in json_dict.get('properties'):
             property = ParsedProperty(property_dict)
             property.class_name = self.name
             
             # TODO: We should handle all properties?
             if property.should_ignore_property():
                 print 'Ignoring property:', property.name
                 continue
             
             self.property_map[property.name] = property

     def properties(self):
         result = []
         for name in sorted(self.property_map.keys()):
             result.append(self.property_map[name])
         return result

     def database_subclass_properties(self):
        # More than one subclass of a SDS model may declare properties
        # with the same name.  This is fine, so long as they have
        # the same type.
        all_property_map = {}
        subclass_property_map = {}
        root_property_names = set()
        
        # print 'properties from:', clazz.name
        for property in self.properties():
            all_property_map[property.name] = property
            root_property_names.add(property.name)
        
        for subclass in all_descendents_of_class(self):
            # print 'properties from subclass:', subclass.name
            for property in subclass.properties():
                
                duplicate_property = all_property_map.get(property.name)
                if duplicate_property is not None:
                    # print '\t', 'duplicate', property.name
                    if property.swift_type_safe() != duplicate_property.swift_type_safe():
                        print 'property:', property.class_name, property.name, property.swift_type_safe(), property.is_optional
                        print 'duplicate_property:', duplicate_property.class_name, duplicate_property.name, duplicate_property.swift_type_safe(), duplicate_property.is_optional
                        fail("Duplicate property doesn't match:", property.name)
                    elif property.is_optional != duplicate_property.is_optional:
                        if property.name in root_property_names:
                            print 'property:', property.class_name, property.name, property.swift_type_safe(), property.is_optional
                            print 'duplicate_property:', duplicate_property.class_name, duplicate_property.name, duplicate_property.swift_type_safe(), duplicate_property.is_optional
                            fail("Duplicate property doesn't match:", property.name)
                        
                        # If one subclass property is optional and the other isn't, we should 
                        # treat both as optional for the purposes of the database schema.
                        if not property.is_optional:
                            continue
                    else:
                        continue
                    
                # print 'adding', property.name
                all_property_map[property.name] = property
                subclass_property_map[property.name] = property
                
        result = []
        for name in sorted(subclass_property_map.keys()):
            result.append(subclass_property_map[name])
        return result
                    
     
     def is_sds_model(self):
         if self.super_class_name is None:
             print 'is_sds_model (1):', self.name, self.super_class_name
             return False
         if not self.super_class_name in global_class_map:
             print 'is_sds_model (2):', self.name, self.super_class_name
             return False
         if self.super_class_name == BASE_MODEL_CLASS_NAME:
             print 'is_sds_model (3):', self.name, self.super_class_name
             return True
         super_class = global_class_map[self.super_class_name]
         print 'is_sds_model (4):', self.name, self.super_class_name
         return super_class.is_sds_model()
     
     def has_sds_superclass(self):
         # print 'has_sds_superclass'
         # print 'self.super_class_name:', self.super_class_name, self.super_class_name in global_class_map, self.super_class_name != BASE_MODEL_CLASS_NAME
         return (self.super_class_name and
                self.super_class_name in global_class_map
                and self.super_class_name != BASE_MODEL_CLASS_NAME)
        
     def table_superclass(self):
         if self.super_class_name is None:
             return self
         if not self.super_class_name in global_class_map:
             return self
         if self.super_class_name == BASE_MODEL_CLASS_NAME:
             return self
         super_class = global_class_map[self.super_class_name]
         return super_class.table_superclass()
    
        
class TypeInfo:
    def __init__(self, swift_type, objc_type, should_use_blob = False, is_enum = False):
        self._swift_type = swift_type
        self._objc_type = objc_type
        self.should_use_blob = should_use_blob
        self.is_enum = is_enum
    # def objc_type_safe(self):
    #     return self.type_info().objc_type()
    #     if self.objc_type is None:
    #         fail("Don't know Obj-C type for:", self.name)
    #     return self.objc_type

    def swift_type(self):
        return self._swift_type

    def objc_type(self):
        return self._objc_type

    # This defines the mapping of Swift types to database column types. 
    # We'll be iterating on this mapping. 
    # Note that we currently store all sub-models and collections (e.g. [String]) as a blob.
    #
    # TODO:
    def database_column_type(self, value_name):
        # print 'self._swift_type', self._swift_type, self._objc_type
        # Special case this oddball type.
        if value_name == 'conversationColorName':
            return '.unicodeString'
        elif self.should_use_blob:
            return '.blob'
        elif self.is_enum:
            return '.int'
        elif self._swift_type == 'String':
            return '.unicodeString'
        elif self._swift_type == 'Date':
            return '.int64'
        elif self._swift_type == 'Data':
            return '.blob'
        elif self._swift_type == 'Bool':
            return '.int'
        elif self._swift_type == 'UInt32':
            return '.int'
        elif self._swift_type in ('Double', 'Float'):
            return '.double'
        elif self.is_numeric():
            return '.int64'
        else:
            fail('Unknown type(1):', self._swift_type)

    def is_numeric(self):
        # TODO: We need to revisit how we serialize numeric types.
        return self._swift_type in (
            # 'signed char',
            'Bool',
            'UInt64',
            'UInt',
            'Int64',
            'Int',
            'Int32',
            'UInt32',
            'Double',
            'Float'
        )

    def should_cast_to_swift(self):
        if self._swift_type in ('Bool', 'Int64', 'UInt64',):
            return False
        return self.is_numeric()
                  
    # This defines how to deserialize database column values to Swift values, using SDSDeserializer.
    def deserializer_invocation(self, column_index_name, value_name, is_optional):
        
        # Special case this oddball type.
        if value_name == 'conversationColorName':
            accessor_name = 'optionalString' if is_optional else 'string'
        elif self.should_use_blob:
            accessor_name = 'optionalBlob' if is_optional else 'blob'
        elif self.is_enum:
            accessor_name = 'optionalInt' if is_optional else 'int'
        elif self._swift_type == 'String':
            accessor_name = 'optionalString' if is_optional else 'string'
        elif self._swift_type == 'Date':
            accessor_name = 'optionalDate' if is_optional else 'date'
        elif self._swift_type == 'Data':
            accessor_name = 'optionalBlob' if is_optional else 'blob'
        elif self._swift_type == 'Bool':
            # TODO: We'll want to use Bool? for Swift models.
            accessor_name = 'optionalBoolAsNSNumber' if is_optional else 'bool'
        elif self._swift_type == 'Int64':
            accessor_name = 'optionalInt64AsNSNumber' if is_optional else 'int64'
        elif self._swift_type == 'UInt64':
            accessor_name = 'optionalUInt64AsNSNumber' if is_optional else 'uint64'
        elif self._swift_type in ('Double', 'Float'):
            accessor_name = 'optionalDoubleAsNSNumber' if is_optional else 'double'
        elif self.is_numeric():
            accessor_name = 'optionalInt64' if is_optional else 'int64'
        else:
            fail('Unknown type(2):', self._swift_type)
            
        value_expr = 'try deserializer.%s(at: %s)' % ( accessor_name, str(column_index_name), )
        if self.should_cast_to_swift() and not is_optional:
            value_expr = str(self._swift_type) + '(' + value_expr + ')'

        # Special case this oddball type.
        if value_name == 'conversationColorName':
            value_statement = 'let %s = ConversationColorName(rawValue: %s)' % ( value_name, value_expr, )
        elif self.should_use_blob:
            blob_name = '%sSerialized' % ( str(value_name), )
            if is_optional:
                serialized_statement = 'let %s: Data? = %s' % ( blob_name, value_expr, )
                value_statement = 'let %s: %s? = try SDSDeserializer.optionalUnarchive(%s)' % ( value_name, self._swift_type, blob_name, )
            else:
                serialized_statement = 'let %s: Data = %s' % ( blob_name, value_expr, )
                value_statement = 'let %s: %s = try SDSDeserializer.unarchive(%s)' % ( value_name, self._swift_type, blob_name, )
            return [ serialized_statement, value_statement,]
        elif self.is_enum:
            # print 'self._swift_type', self._swift_type
            enum_type = swift_type_for_enum(self._swift_type)
            raw_name = '%sRaw' % ( str(value_name), )
            return [ 
                    'let %s = %s(%s)' % ( raw_name, str(enum_type), value_expr, ),
                    'guard let %s = %s(rawValue: %s) else {' % ( value_name, self._swift_type, raw_name, ),
                    '   throw SDSError.invalidValue',
                    '}',
                ]
        elif is_optional and self._objc_type == 'NSNumber *':
            return [ 
                    'let %s = %s' % ( value_name, value_expr, ),
                    # 'let %sRaw = %s' % ( value_name, value_expr, ),
                    # 'var %s : NSNumber?' % ( value_name, ),
                    # 'if let value = %sRaw {' % ( value_name, ),
                    # '   %s = NSNumber(value: value)' % ( value_name, ),
                    # '}',
                ]
        else:
            value_statement = 'let %s = %s' % ( value_name, value_expr, )
        return [value_statement,]
        
        
class ParsedProperty:
    def __init__(self, json_dict):
        self.name = json_dict.get('name')
        self.is_optional = json_dict.get('is_optional')
        self.objc_type = json_dict.get('objc_type')
        self.class_name = json_dict.get('class_name')
        self.swift_type = None            
            
    def try_to_convert_objc_primitive_to_swift(self, objc_type, unpack_nsnumber=True):
        if objc_type is None:
            fail('Missing type')
        elif objc_type == 'NSString *':
            return 'String'
        elif objc_type == 'NSDate *':
            return 'Date'
        elif objc_type == 'NSData *':
            return 'Data'
        elif objc_type == 'BOOL':
            return 'Bool'
        elif objc_type == 'NSInteger':
            return 'Int'
        elif objc_type == 'NSUInteger':
            return 'UInt'
        elif objc_type == 'int32_t':
            return 'Int32'
        elif objc_type == 'unsigned long long':
            return 'UInt64'
        elif objc_type == 'unsigned long':
            return 'UInt64'
        elif objc_type == 'unsigned int':
            return 'UInt32'
        elif objc_type == 'double':
            return 'Double'
        elif objc_type == 'float':
            return 'Float'
        elif objc_type == 'CGFloat':
            return 'Double'
        elif objc_type == 'NSNumber *':
            if unpack_nsnumber:
                return swift_type_for_nsnumber(self)
            else:
                return 'NSNumber'
        else:
            return None
    
    
    # NOTE: This method recurses to unpack types like: NSArray<NSArray<SomeClassName *> *> *
    def convert_objc_class_to_swift(self, objc_type, unpack_nsnumber=True):
        if not objc_type.endswith(' *'):
            return None
        
        swift_primitive = self.try_to_convert_objc_primitive_to_swift(objc_type, unpack_nsnumber=unpack_nsnumber)
        if swift_primitive is not None:
            return swift_primitive
        
        array_match = re.search(r'^NS(Mutable)?Array<(.+)> \*$', objc_type)
        if array_match is not None:
            split = array_match.group(2)
            return '[' + self.convert_objc_class_to_swift(split, unpack_nsnumber=False) + ']'
        
        dict_match = re.search(r'^NS(Mutable)?Dictionary<(.+),(.+)> \*$', objc_type)
        if dict_match is not None:
            split1 = dict_match.group(2).strip()
            split2 = dict_match.group(3).strip()
            return '[' + self.convert_objc_class_to_swift(split1, unpack_nsnumber=False) + ': ' + self.convert_objc_class_to_swift(split2, unpack_nsnumber=False) + ']'
        
        swift_type = objc_type[:-len(' *')]
        
        if '<' in swift_type or '{' in swift_type or '*' in swift_type:
            fail('Unexpected type:', objc_type)
        return swift_type
            
            
    def try_to_convert_objc_type_to_type_info(self):
        objc_type = self.objc_type

        if objc_type is None:
            fail('Missing type')
            
        elif is_flagged_as_enum_property(self):
            enum_type = objc_type
            return TypeInfo(enum_type, objc_type, is_enum=True)
        elif objc_type in enum_type_map:
            enum_type = objc_type
            return TypeInfo(enum_type, objc_type, is_enum=True)
        elif objc_type.startswith('enum '):
            enum_type = objc_type[len('enum '):]
            return TypeInfo(enum_type, objc_type, is_enum=True)

        swift_primitive = self.try_to_convert_objc_primitive_to_swift(objc_type)
        if swift_primitive is not None:
            return TypeInfo(swift_primitive, objc_type)
        
        # print 'objc_type', objc_type
        if objc_type in ('struct CGSize',):
            objc_type = objc_type[len('struct '):]
            swift_type = objc_type
            return TypeInfo(swift_type, objc_type, should_use_blob=True)

        swift_type = self.convert_objc_class_to_swift(self.objc_type)
        if swift_type is not None:
            return TypeInfo(swift_type, objc_type, should_use_blob=True)
        
        fail('Unknown type(3):', self.class_name, self.objc_type, self.name)
        
    def type_info(self):
        if self.swift_type is not None:
            should_use_blob = (self.swift_type.startswith('[') or self.swift_type.startswith('{') or is_swift_class_name(self.swift_type))
            return TypeInfo(self.swift_type, objc_type, should_use_blob=should_use_blob)
        
        return self.try_to_convert_objc_type_to_type_info()

    def swift_type_safe(self):
        return self.type_info().swift_type()

    def objc_type_safe(self):
        return self.type_info().objc_type()
        # if self.objc_type is None:
        #     fail("Don't know Obj-C type for:", self.name)
        # return self.objc_type

    def database_column_type(self):
        return self.type_info().database_column_type(self.name)

    def should_ignore_property(self):
        return should_ignore_property(self)

    def deserializer_invocation(self, column_index_name, value_name):
        return self.type_info().deserializer_invocation(column_index_name, value_name, self.is_optional)

 
def ows_getoutput(cmd):
    proc = subprocess.Popen(cmd,
        stdout = subprocess.PIPE,
        stderr = subprocess.PIPE,
    )
    stdout, stderr = proc.communicate()
 
    return proc.returncode, stdout, stderr


# ---- Parsing

def properties_and_inherited_properties(clazz):
    result = []
    if clazz.super_class_name in global_class_map:
        super_class = global_class_map[clazz.super_class_name]
        result.extend(properties_and_inherited_properties(super_class))
    result.extend(clazz.properties())
    # for property in result:
    #     print '----', clazz.name, '----', property.name
    return result


def generate_swift_extensions_for_model(clazz):
    print '\t', 'processing', clazz.__dict__
    
    if clazz.name == BASE_MODEL_CLASS_NAME:
        print 'Ignoring class (1):', clazz.name 
        return
    if should_ignore_class(clazz):
        print 'Ignoring class (2):', clazz.name 
        return
    
    has_sds_superclass = clazz.has_sds_superclass()
    if not clazz.is_sds_model():
        # Only write serialization extensions for SDS models.
        print 'Ignoring class (3):', clazz.name 
        return

    print '\t', '\t', 'clazz.name', clazz.name, type(clazz.name)
    print '\t', '\t', 'clazz.super_class_name', clazz.super_class_name
    print '\t', '\t', 'filepath', clazz.filepath
    print '\t', '\t', 'table_superclass', clazz.table_superclass().name
    print '\t', '\t', 'has_sds_superclass', has_sds_superclass
    
    swift_filename = os.path.basename(clazz.filepath)
    swift_filename = swift_filename[:swift_filename.find('.')] + '+SDS.swift'
    swift_filepath = os.path.join(os.path.dirname(clazz.filepath), swift_filename)
    print '\t', '\t', 'swift_filepath', swift_filepath
    
    record_type = get_record_type(clazz)
    print '\t', '\t', 'record_type', record_type
    
    # TODO: We'll need to import SignalServiceKit for non-SSK models.
    
    swift_body = '''//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalCoreKit

// NOTE: This file is generated by %s. 
// Do not manually edit it, instead run `sds_codegen.sh`.
''' % ( sds_common.pretty_module_path(__file__), )

    if not has_sds_superclass:
        swift_body += '''
// MARK: - SDSSerializable

extension %s: SDSSerializable {
    public var serializer: SDSSerializer {
        // Any subclass can be cast to it's superclass,
        // so the order of this switch statement matters.
        // We need to do a "depth first" search by type.
        switch self {''' % str(clazz.name)

        for subclass in reversed(all_descendents_of_class(clazz)):
            swift_body += '''
        case let model as %s:
            assert(type(of: model) == %s.self)
            return %sSerializer(model: model)''' % ( str(subclass.name), str(subclass.name), str(subclass.name), )

        swift_body += '''
        default:
            return %sSerializer(model: self)
        }
    }
}
''' % ( str(clazz.name), )

    
    if not has_sds_superclass:
        swift_body += '''
// MARK: - Table Metadata

extension %sSerializer {

    // This defines all of the columns used in the table 
    // where this model (and any subclasses) are persisted.
    static let recordTypeColumn = SDSColumnMetadata(columnName: "recordType", columnType: .int, columnIndex: 0)
    static let uniqueIdColumn = SDSColumnMetadata(columnName: "uniqueId", columnType: .unicodeString, columnIndex: 1)
''' % str(clazz.name)

        # Eventually we need a (persistent?) mechanism for guaranteeing
        # consistency of column ordering, that is robust to schema 
        # changes, class hierarchy changes, etc. 
        column_property_names = []
        column_property_names.append('recordType')
        column_property_names.append('uniqueId')

        def write_column_metadata(property, force_optional=False):
            column_index = len(column_property_names)
            column_name = to_swift_identifer_name(property.name)
            column_property_names.append(column_name)
            
            is_optional = property.is_optional or force_optional
            optional_split = ', isOptional: true' if is_optional else ''
            
            # print 'property', property.swift_type_safe()
            database_column_type = property.database_column_type()
            
            # TODO: Use skipSelect.
            return '''    static let %sColumn = SDSColumnMetadata(columnName: "%s", columnType: %s%s, columnIndex: %s)
''' % ( str(column_name), str(column_name), database_column_type, optional_split, str(column_index) )
        
        # print 'properties from:', clazz.name
        if len(clazz.properties()) > 0:
            swift_body += '    // Base class properties \n'
            for property in clazz.properties():
                swift_body += write_column_metadata(property)
        
        if len(clazz.database_subclass_properties()) > 0:
            swift_body += '    // Subclass properties \n'
            for property in clazz.database_subclass_properties():
                swift_body += write_column_metadata(property, force_optional=True)          
    
        database_table_name = 'model_%s' % str(clazz.name)
        swift_body += '''
    // TODO: We should decide on a naming convention for
    //       tables that store models.
    public static let table = SDSTableMetadata(tableName: "%s", columns: [
''' % database_table_name

        for column_property_name in column_property_names:
            swift_body += '''        %sColumn,
''' % ( str(column_property_name) )
        swift_body += '''        ])
''' 

        swift_body += '''
}

// MARK: - Deserialization

extension %sSerializer {
    // This method defines how to deserialize a model, given a 
    // database row.  The recordType column is used to determine
    // the corresponding model class.
    class func sdsDeserialize(statement: SelectStatement) throws -> %s {
''' % ( str(clazz.name), str(clazz.name) )
        swift_body += '''
        if OWSIsDebugBuild() {
            guard statement.columnNames == table.selectColumnNames else {
                owsFailDebug("Unexpected columns: \(statement.columnNames) != \(table.selectColumnNames)")
                throw SDSError.invalidResult
            }
        }
        
        // SDSDeserializer is used to convert column values into Swift values.
        let deserializer = SDSDeserializer(sqliteStatement: statement.sqliteStatement)
        let recordTypeValue = try deserializer.int(at: 0)
        guard let recordType = SDSRecordType(rawValue: UInt(recordTypeValue)) else {
            owsFailDebug("Invalid recordType: \(recordTypeValue)")
            throw SDSError.invalidResult
        }
        switch recordType {
'''

        deserialize_classes = all_descendents_of_class(clazz) + [clazz]
        
        for deserialize_class in deserialize_classes:
            initializer_params = []
            objc_initializer_params = []
            deserialize_record_type = get_record_type_enum_name(deserialize_class.name)
            swift_body += '''        case .%s:
''' % ( str(deserialize_record_type), )

            swift_body += '''
            let uniqueId = try deserializer.string(at: uniqueIdColumn.columnIndex)
'''

            deserialize_properties = properties_and_inherited_properties(deserialize_class)
            for property in deserialize_properties:
                database_column_type = property.database_column_type()
                column_name = str(property.name)
                column_index_name = '%sColumn.columnIndex' % ( str(column_name), )
                value_name = '%s' % ( str(column_name), )
                
                if property.name != 'uniqueId':
                    for statement in property.deserializer_invocation(column_index_name, value_name):
                        # print 'statement', statement, type(statement)
                        swift_body += '            %s\n' % ( str(statement), )
                
                initializer_params.append('%s: %s' % ( str(property.name), value_name, ) )
                objc_initializer_type = str(property.objc_type_safe())
                if objc_initializer_type.startswith('NSMutable'):
                    objc_initializer_type = 'NS' + objc_initializer_type[len('NSMutable'):]
                if property.is_optional:
                    objc_initializer_type = 'nullable ' + objc_initializer_type
                objc_initializer_params.append('%s:(%s)%s' % ( str(property.name), objc_initializer_type, str(property.name), ) )

            # --- Suggested Initializer

            swift_body += '''
/* Suggested Initializer

- (instancetype)initWithUniqueId:(NSString *)uniqueId
'''
            for objc_initializer_param in objc_initializer_params[1:]:
                alignment = max(0, len('- (instancetype)initWithUniqueId:') - objc_initializer_param.index(':'))
                swift_body += (' ' * alignment) + objc_initializer_param + '\n'

            swift_body += 'NS_DESIGNATED_INITIALIZER \n'
            swift_body += 'NS_SWIFT_NAME(init(%s:));\n' % ':'.join([str(property.name) for property in deserialize_properties])
                
            swift_body += '''*/
'''

            # --- Invoke Initializer
            
            initializer_invocation = '            return %s(' % str(deserialize_class.name)
            swift_body += initializer_invocation
            swift_body += (',\n' + ' ' * len(initializer_invocation)).join(initializer_params)
            swift_body += ')\n\n'

            # TODO: We could generate a comment with the Obj-C (or Swift) model initializer 
            #       that this deserialization code expects.

        swift_body += '''        default:
            owsFail("Invalid record type \(recordType)")
'''

        swift_body += '''        }
''' 
        swift_body += '''    }
''' 
        swift_body += '''}
''' 

        # ---- Fetch ----

        swift_body += '''
// MARK: - Save/Remove/Update

@objc
extension %s {
    @objc
    public func anySave(transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite(let ydbTransaction):
            save(with: ydbTransaction)
        case .grdbWrite(let grdbTransaction):
            SDSSerialization.save(entity: self, transaction: grdbTransaction)
        }
    }

    @objc
    public func anyRemove(transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite(let ydbTransaction):
            remove(with: ydbTransaction)
        case .grdbWrite(let grdbTransaction):
            SDSSerialization.delete(entity: self, transaction: grdbTransaction)
        }
    }
}

// TODO: Add remove/delete method.

''' % ( ( str(clazz.name), ) * 1 )


        # ---- Fetch ----

        swift_body += '''
// MARK: - Fetch

// This category defines various fetch methods.  
//
// TODO: We may eventually want to define some combination of:
//
// * fetchCursor, fetchOne, fetchAll, etc. (ala GRDB)
// * Optional "where clause" parameters for filtering.
// * Async flavors with completions.
//
// TODO: I've defined flavors that take a read transation or SDSDatabaseStorage.
//       We might want only the former.  Or we might take a "connection" if we
//       end up having that class.
@objc
extension %s {
    @objc
    public class func anyFetchAll(databaseStorage: SDSDatabaseStorage) -> [%s] {
        var result = [%s]()
        databaseStorage.readSwallowingErrors { (transaction) in
            result += anyFetchAll(transaction: transaction)
        }
        return result
    }

    @objc
    public class func anyFetchAll(transaction: SDSAnyReadTransaction) -> [%s] {
        var result = [%s]()
        if let grdbTransaction = transaction.transitional_grdbReadTransaction {
            result += SDSSerialization.fetchAll(tableMetadata: %sSerializer.table,
                                                uniqueIdColumnName: %sSerializer.uniqueIdColumn.columnName,
                                                transaction: grdbTransaction,
                                                deserialize: { (statement) in
                                                    return try %sSerializer.sdsDeserialize(statement: statement)
            })
        } else if let ydbTransaction = transaction.transitional_yapReadTransaction {
            %s.enumerateCollectionObjects(with: ydbTransaction) { (object, _) in
                guard let model = object as? %s else {
                    owsFailDebug("unexpected object: \(type(of: object))")
                    return
                }
                result.append(model)
            }
        } else {
            owsFailDebug("Invalid transaction")
        }
        return result
    }
}

// TODO: Add remove/delete method.

''' % ( ( str(clazz.name), ) * 10 )


    # ---- SDSSerializable ----

    table_superclass = clazz.table_superclass()
    table_class_name = str(table_superclass.name)
    has_serializable_superclass = table_superclass.name != clazz.name
    
    override_keyword = ''
    # protocols = ''
    # override_keyword = ''
    # if has_serializable_superclass:
    #     override_keyword = ' override'
    # else:
    #     protocols =  ' : SDSSerializable'
    
    
    swift_body += '''
// MARK: - SDSSerializer

// The SDSSerializer protocol specifies how to insert and update the
// row that corresponds to this model.
class %sSerializer: SDSSerializer {

    private let model: %s
    public required init(model: %s) {
        self.model = model
    }
''' % ( str(clazz.name), str(clazz.name), str(clazz.name), )

    swift_body += '''
    public func serializableColumnTableMetadata() -> SDSTableMetadata {
        return %sSerializer.table
    }
''' % ( table_class_name, )

    swift_body += '''
    public%s func insertColumnNames() -> [String] {
        // When we insert a new row, we include the following columns:
        //
        // * "record type"
        // * "unique id"
        // * ...all columns that we set when updating.        
        return [
            %sSerializer.recordTypeColumn.columnName,
            uniqueIdColumnName(),
            ] + updateColumnNames()
        
    }
    
    public%s func insertColumnValues() -> [DatabaseValueConvertible] {
        let result: [DatabaseValueConvertible] = [
''' % ( override_keyword, table_class_name, override_keyword, )

    serialize_record_type = get_record_type_enum_name(clazz.name)
    swift_body += '''            SDSRecordType.%s.rawValue,''' % ( str(serialize_record_type), )

    swift_body += '''
            ] + [uniqueIdColumnValue()] + updateColumnValues()
        if OWSIsDebugBuild() {
            if result.count != insertColumnNames().count {
                owsFailDebug("Update mismatch: \(result.count) != \(insertColumnNames().count)")
            }
        }
        return result
    }
    
    public%s func updateColumnNames() -> [String] {
        return [
''' % ( override_keyword, )
    
    serialize_properties = properties_and_inherited_properties(clazz)
    for property in serialize_properties:
        if property.name == 'uniqueId':
            continue
        column_name = to_swift_identifer_name(property.name)
        # print 'property:', property.name, property.swift_type_safe()
        swift_body += '''            %sSerializer.%sColumn,
''' % ( str(table_class_name), str(column_name), )

    swift_body += '''            ].map { $0.columnName }
    }
    
    public%s func updateColumnValues() -> [DatabaseValueConvertible] {
        let result: [DatabaseValueConvertible] = [
''' % ( override_keyword, )
            # self.body,
            # self.author ?? DatabaseValue.null,
    for property in serialize_properties:
        if property.name == 'uniqueId':
            continue
        property_accessor = accessor_name_for_property(property)
        # column_name = to_swift_identifer_name(property.name)
        insert_value = 'self.model.%s' % str(property_accessor)

        if property.type_info().is_enum:
            insert_value = insert_value + '.rawValue'

        if property.type_info().should_use_blob:
            insert_value = 'SDSDeserializer.archive(%s) ?? DatabaseValue.null' % ( insert_value, )
        elif property.is_optional:
            insert_value = insert_value + ' ?? DatabaseValue.null'
        swift_body += '''            %s,
''' % ( insert_value, )

    swift_body += '''
        ]
        if OWSIsDebugBuild() {
            if result.count != updateColumnNames().count {
                owsFailDebug("Update mismatch: \(result.count) != \(updateColumnNames().count)")
            }
        }
        return result
    }
'''

    swift_body += '''
    public func uniqueIdColumnName() -> String {
        return %sSerializer.uniqueIdColumn.columnName
    }
    
    // TODO: uniqueId is currently an optional on our models.
    //       We should probably make the return type here String?
    public func uniqueIdColumnValue() -> DatabaseValueConvertible {
        // FIXME remove force unwrap
        return model.uniqueId!
    }
''' % ( table_class_name, )

    swift_body += '''}
''' 

    # print 'swift_body', swift_body
    print 'Writing:', swift_filepath

    swift_body = sds_common.clean_up_generated_swift(swift_body)
    
    # Add some random whitespace to trigger the auto-formatter.
    swift_body = swift_body + (' ' * random.randint(1, 100))

    with open(swift_filepath, 'wt') as f:
        f.write(swift_body)
        

def process_class_map(class_map):
    print 'processing', class_map
    for clazz in class_map.values():
        generate_swift_extensions_for_model(clazz)


# ---- Record Type Map

record_type_map = {}

# It's critical that our "record type" values are consistent, even if we add/remove/rename model classes. 
# Therefore we persist the mapping of known classes in a JSON file that is under source control.
def update_record_type_map(record_type_swift_path, record_type_json_path):
    print 'update_record_type_map'
    
    record_type_map_filepath = record_type_json_path

    if os.path.exists(record_type_map_filepath):
        with open(record_type_map_filepath, 'rt') as f:
            json_string = f.read()
        json_data = json.loads(json_string)
        record_type_map.update(json_data)
    
    max_record_type = 0
    for class_name in record_type_map:
        if class_name.startswith('#'):
            continue
        record_type = record_type_map[class_name]
        max_record_type = max(max_record_type, record_type)
    
    for clazz in global_class_map.values():
        if clazz.name not in record_type_map:
            
            if clazz.name == BASE_MODEL_CLASS_NAME:
                print 'Ignoring class (1):', clazz.name 
                continue
            if should_ignore_class(clazz):
                print 'Ignoring class (2):', clazz.name 
                continue
    
            if not clazz.is_sds_model():
                # Only write serialization extensions for SDS models.
                print 'Ignoring class (3):', clazz.name 
                continue
            
            
            max_record_type = int(max_record_type) + 1
            record_type = max_record_type
            record_type_map[clazz.name] = record_type

    record_type_map['#comment'] = 'NOTE: This file is generated by %s. Do not manually edit it, instead run `sds_codegen.sh`.' % ( sds_common.pretty_module_path(__file__), )

    json_string = json.dumps(record_type_map, sort_keys=True, indent=4)
    with open(record_type_map_filepath, 'wt') as f:
        f.write(json_string)

    
    # TODO: We'll need to import SignalServiceKit for non-SSK classes.
        
    swift_body = '''//
//  Copyright © 2019 Signal. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalCoreKit

// NOTE: This file is generated by %s. 
// Do not manually edit it, instead run `sds_codegen.sh`.

@objc
public enum SDSRecordType: UInt {
''' % ( sds_common.pretty_module_path(__file__), )
    for key in sorted(record_type_map.keys()):
        if key.startswith('#'):
            # Ignore comments
            continue
        enum_name = get_record_type_enum_name(key)
        # print 'enum_name', enum_name
        swift_body += '''    case %s = %s
''' % ( str(enum_name), str(record_type_map[key]), )
        
    swift_body += '''}
''' 
    # print 'swift_body', swift_body

    swift_body = sds_common.clean_up_generated_swift(swift_body)

    with open(record_type_swift_path, 'wt') as f:
        f.write(swift_body)



def get_record_type(clazz):
    return record_type_map[clazz.name]


def get_record_type_enum_name(class_name):
    name = class_name
    if name.startswith('TS'):
        name = name[len('TS'):]
    elif name.startswith('OWS'):
        name = name[len('OWS'):]
    return to_swift_identifer_name(name)
    

# ---- Column Ordering


column_ordering_map = {}
has_loaded_column_ordering_map = False


# ---- Parsing

enum_type_map = {}

def objc_type_for_enum(enum_name):
    if enum_name not in enum_type_map:
        print 'enum_type_map', enum_type_map
        fail('Enum has unknown type:', enum_name)
    enum_type = enum_type_map[enum_name]
    return enum_type
    
def swift_type_for_enum(enum_name):
    objc_type = objc_type_for_enum(enum_name)
    
    if objc_type == 'NSInteger':
        return 'Int'
    elif objc_type == 'NSUInteger':
        return 'UInt'
    elif objc_type == 'int32_t':
        return 'Int32'
    elif objc_type == 'unsigned long long':
        return 'UInt64'
    elif objc_type == 'unsigned long':
        return 'UInt64'
    elif objc_type == 'unsigned int':
        return 'UInt'
    else:
        fail('Unknown objc type:', objc_type)

    
def parse_sds_json(file_path):
    with open(file_path, 'rt') as f:
        json_str = f.read()
    json_data = json.loads(json_str)
    # print 'json_data:', json_data
    
    classes = json_data['classes']
    class_map = {}
    for class_dict in classes:
        # print 'class_dict:', class_dict
        clazz = ParsedClass(class_dict)
        class_map[clazz.name] = clazz
        
    enums = json_data['enums']
    # print '---- enums', file_path
    # print '---- enums', enums
    enum_type_map.update(enums)
    
    return class_map
        

def try_to_parse_file(file_path):
    filename = os.path.basename(file_path)
    # print 'filename', filename
    _, file_extension = os.path.splitext(filename)
    if filename.endswith(sds_common.SDS_JSON_FILE_EXTENSION):
        # print 'filename:', filename
        print '\t', 'found', file_path
        return parse_sds_json(file_path)
    else:   
        return {}
        

def find_sds_intermediary_files_in_path(path):
    print 'find_sds_intermediary_files_in_path', path
    class_map = {}
    if os.path.isfile(path):
        class_map.update(try_to_parse_file(path))
    else:
        for rootdir, dirnames, filenames in os.walk(path):
            for filename in filenames:
                file_path = os.path.abspath(os.path.join(rootdir, filename))
                class_map.update(try_to_parse_file(file_path))
    return class_map    


def update_subclass_map():
    for clazz in global_class_map.values():
        if clazz.super_class_name is not None:
            subclasses = global_subclass_map.get(clazz.super_class_name, [])
            subclasses.append(clazz)
            global_subclass_map[clazz.super_class_name] = subclasses


def all_descendents_of_class(clazz):
    result = []
    
    # print 'descendents of:', clazz.name
    # print '\t', global_subclass_map.get(clazz.name, [])
    for subclass in global_subclass_map.get(clazz.name, []):
        result.append(subclass)
        result.extend(all_descendents_of_class(subclass))
        
    return result


def is_swift_class_name(swift_type):
    return global_class_map.get(swift_type) is not None

    
# ---- Config JSON

configuration_json = {}

def parse_config_json(config_json_path):
    print 'config_json_path', config_json_path
    
    with open(config_json_path, 'rt') as f:
        json_str = f.read()
    
    json_data = json.loads(json_str)
    global configuration_json
    configuration_json = json_data


# We often use nullable NSNumber * for optional numerics (bool, int, int64, double, etc.). 
# There's now way to infer which type we're boxing in NSNumber. 
# Therefore, we need to specify that in the configuration JSON.
def swift_type_for_nsnumber(property):
    nsnumber_types = configuration_json.get('nsnumber_types')
    if nsnumber_types is None:
        print 'Suggestion: update: %s' % ( str(global_args.config_json_path), )
        fail('Configuration JSON is missing mapping for properties of type NSNumber.')
    key = property.class_name + '.' + property.name
    swift_type = nsnumber_types.get(key)
    if swift_type is None:
        print 'Suggestion: update: %s' % ( str(global_args.config_json_path), )
        fail('Configuration JSON is missing mapping for properties of type NSNumber:', key)
    return swift_type    



# Some properties shouldn't get serialized. 
# For now, there's just one: TSGroupModel.groupImage which is a UIImage.
# We might end up extending the serialization to handle images. 
# Or we might store these as Data/NSData/blob. 
# TODO:
def should_ignore_property(property):
    properties_to_ignore = configuration_json.get('properties_to_ignore')
    if properties_to_ignore is None:
        fail('Configuration JSON is missing list of properties to ignore during serialization.')
    key = property.class_name + '.' + property.name
    return key in properties_to_ignore


def should_ignore_class(clazz):
    class_to_skip_serialization = configuration_json.get('class_to_skip_serialization')
    if class_to_skip_serialization is None:
        fail('Configuration JSON is missing list of classes to ignore during serialization.')
    return clazz.name in class_to_skip_serialization


def is_flagged_as_enum_property(property):
    enum_properties = configuration_json.get('enum_properties')
    if enum_properties is None:
        fail('Configuration JSON is missing list of properties to treat as enums.')
    key = property.class_name + '.' + property.name
    return key in enum_properties


def accessor_name_for_property(property):
    custom_accessors = configuration_json.get('custom_accessors')
    if custom_accessors is None:
        fail('Configuration JSON is missing list of custom property accessors.')
    key = property.class_name + '.' + property.name
    # print '--?--', key, custom_accessors.get(key, property.name)
    return custom_accessors.get(key, property.name)


if __name__ == "__main__":
    
    parser = argparse.ArgumentParser(description='Parse Swift AST.')
    parser.add_argument('--src-path', required=True, help='used to specify a path to process.')
    parser.add_argument('--search-path', required=True, help='used to specify a path to process.')
    parser.add_argument('--record-type-swift-path', required=True, help='path of the record type enum swift file.')
    parser.add_argument('--record-type-json-path', required=True, help='path of the record type map json file.')
    parser.add_argument('--config-json-path', required=True, help='path of the json file with code generation config info.')
    args = parser.parse_args()
    
    global global_args
    global_args = args
    
    src_path = os.path.abspath(args.src_path)
    search_path = os.path.abspath(args.search_path)
    record_type_swift_path = os.path.abspath(args.record_type_swift_path)
    record_type_json_path = os.path.abspath(args.record_type_json_path)
    config_json_path = os.path.abspath(args.config_json_path)
    
    
    # We control the code generation process using a JSON config file.
    print
    print 'Parsing Config'
    parse_config_json(config_json_path)
    
    # The code generation needs to understand the class hierarchy so that
    # it can:
    #
    # * Define table schemas that include the superset of properties in 
    #   the model class hierarchies.
    # * Generate deserialization methods that handle all subclasses.
    # * etc.
    print
    print 'Parsing Global Class Map'
    global_class_map.update(find_sds_intermediary_files_in_path(search_path))
    print 'global_class_map', global_class_map

    update_subclass_map()
    
    print
    print 'Parsing Record Type Map'
    update_record_type_map(record_type_swift_path, record_type_json_path)

    print
    print 'Processing'
    process_class_map(find_sds_intermediary_files_in_path(src_path))

module

public import Protobuf.Encoding
public import Protobuf.ProtoMessage
public import Protobuf.Base64
public import Protobuf.Reflection
meta import Protobuf.Notation
public import Protobuf.Internal.Desc

public section

open Protobuf Encoding
open scoped Protobuf.Notation
enum «google».«protobuf».«compiler».«CodeGeneratorResponse».«Feature» [ «closed» = true ] {
  «FEATURE_NONE» = 0;
  «FEATURE_PROTO3_OPTIONAL» = 1;
  «FEATURE_SUPPORTS_EDITIONS» = 2;
}

message «google».«protobuf».«compiler».«Version» {
  optional «int32» «major» = 1;
  optional «int32» «minor» = 2;
  optional «int32» «patch» = 3;
  optional «raw_string» «suffix» = 4;
}

message «google».«protobuf».«compiler».«CodeGeneratorRequest» {
  repeated «raw_string» «file_to_generate» = 1;
  optional «raw_string» «parameter» = 2;
  repeated «google».«protobuf».«FileDescriptorProto» «proto_file» = 15;
  repeated «google».«protobuf».«FileDescriptorProto» «source_file_descriptors» = 17;
  optional «google».«protobuf».«compiler».«Version» «compiler_version» = 3;
}

message «google».«protobuf».«compiler».«CodeGeneratorResponse».«File» {
  optional «raw_string» «name» = 1;
  optional «raw_string» «insertion_point» = 2;
  optional «raw_string» «content» = 15;
  optional «google».«protobuf».«GeneratedCodeInfo» «generated_code_info» = 16;
}

message «google».«protobuf».«compiler».«CodeGeneratorResponse» {
  optional «raw_string» «error» = 1;
  optional «uint64» «supported_features» = 2;
  optional «int32» «minimum_edition» = 3;
  optional «int32» «maximum_edition» = 4;
  repeated «google».«protobuf».«compiler».«CodeGeneratorResponse».«File» «file» = 15;
}

 private  initialize  «protobuf.fileDescriptor.676f6f676c652f70726f746f6275662f636f6d70696c65722f706c7567696e2e70726f746f»  :  «Protobuf».«Reflection».«FileDescriptor»  ←  «Protobuf».«Reflection».«generatedPool».«registerFileBase64!»  "CiVnb29nbGUvcHJvdG9idWYvY29tcGlsZXIvcGx1Z2luLnByb3RvEhhnb29nbGUucHJvdG9idWYuY29tcGlsZXIaIGdvb2dsZS9wcm90b2J1Zi9kZXNjcmlwdG9yLnByb3RvImMKB1ZlcnNpb24SFAoFbWFqb3IYASABKAVSBW1ham9yEhQKBW1pbm9yGAIgASgFUgVtaW5vchIUCgVwYXRjaBgDIAEoBVIFcGF0Y2gSFgoGc3VmZml4GAQgASgJUgZzdWZmaXgizwIKFENvZGVHZW5lcmF0b3JSZXF1ZXN0EigKEGZpbGVfdG9fZ2VuZXJhdGUYASADKAlSDmZpbGVUb0dlbmVyYXRlEhwKCXBhcmFtZXRlchgCIAEoCVIJcGFyYW1ldGVyEkMKCnByb3RvX2ZpbGUYDyADKAsyJC5nb29nbGUucHJvdG9idWYuRmlsZURlc2NyaXB0b3JQcm90b1IJcHJvdG9GaWxlElwKF3NvdXJjZV9maWxlX2Rlc2NyaXB0b3JzGBEgAygLMiQuZ29vZ2xlLnByb3RvYnVmLkZpbGVEZXNjcmlwdG9yUHJvdG9SFXNvdXJjZUZpbGVEZXNjcmlwdG9ycxJMChBjb21waWxlcl92ZXJzaW9uGAMgASgLMiEuZ29vZ2xlLnByb3RvYnVmLmNvbXBpbGVyLlZlcnNpb25SD2NvbXBpbGVyVmVyc2lvbiKFBAoVQ29kZUdlbmVyYXRvclJlc3BvbnNlEhQKBWVycm9yGAEgASgJUgVlcnJvchItChJzdXBwb3J0ZWRfZmVhdHVyZXMYAiABKARSEXN1cHBvcnRlZEZlYXR1cmVzEicKD21pbmltdW1fZWRpdGlvbhgDIAEoBVIObWluaW11bUVkaXRpb24SJwoPbWF4aW11bV9lZGl0aW9uGAQgASgFUg5tYXhpbXVtRWRpdGlvbhJICgRmaWxlGA8gAygLMjQuZ29vZ2xlLnByb3RvYnVmLmNvbXBpbGVyLkNvZGVHZW5lcmF0b3JSZXNwb25zZS5GaWxlUgRmaWxlGrEBCgRGaWxlEhIKBG5hbWUYASABKAlSBG5hbWUSJwoPaW5zZXJ0aW9uX3BvaW50GAIgASgJUg5pbnNlcnRpb25Qb2ludBIYCgdjb250ZW50GA8gASgJUgdjb250ZW50ElIKE2dlbmVyYXRlZF9jb2RlX2luZm8YECABKAsyIi5nb29nbGUucHJvdG9idWYuR2VuZXJhdGVkQ29kZUluZm9SEWdlbmVyYXRlZENvZGVJbmZvIlcKB0ZlYXR1cmUSEAoMRkVBVFVSRV9OT05FEAASGwoXRkVBVFVSRV9QUk9UTzNfT1BUSU9OQUwQARIdChlGRUFUVVJFX1NVUFBPUlRTX0VESVRJT05TEAJCcgocY29tLmdvb2dsZS5wcm90b2J1Zi5jb21waWxlckIMUGx1Z2luUHJvdG9zWilnb29nbGUuZ29sYW5nLm9yZy9wcm90b2J1Zi90eXBlcy9wbHVnaW5wYqoCGEdvb2dsZS5Qcm90b2J1Zi5Db21waWxlcg==" 

 instance  :  «Protobuf».«Reflection».«ReflectEnum»  «google».«protobuf».«compiler».«CodeGeneratorResponse».«Feature»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«EnumDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "google.protobuf.compiler.CodeGeneratorResponse.Feature"  ,  «toInt32»  :=  «google».«protobuf».«compiler».«CodeGeneratorResponse».«Feature».«protobuf.internal».«toInt32»  ,  «fromInt32»  :=  «google».«protobuf».«compiler».«CodeGeneratorResponse».«Feature».«protobuf.internal».«fromInt32»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «google».«protobuf».«compiler».«Version»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "google.protobuf.compiler.Version"  ,  «toMessagePartial»  :=  «google».«protobuf».«compiler».«Version».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «google».«protobuf».«compiler».«Version».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «google».«protobuf».«compiler».«CodeGeneratorRequest»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "google.protobuf.compiler.CodeGeneratorRequest"  ,  «toMessagePartial»  :=  «google».«protobuf».«compiler».«CodeGeneratorRequest».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «google».«protobuf».«compiler».«CodeGeneratorRequest».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «google».«protobuf».«compiler».«CodeGeneratorResponse»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "google.protobuf.compiler.CodeGeneratorResponse"  ,  «toMessagePartial»  :=  «google».«protobuf».«compiler».«CodeGeneratorResponse».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «google».«protobuf».«compiler».«CodeGeneratorResponse».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «google».«protobuf».«compiler».«CodeGeneratorResponse».«File»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "google.protobuf.compiler.CodeGeneratorResponse.File"  ,  «toMessagePartial»  :=  «google».«protobuf».«compiler».«CodeGeneratorResponse».«File».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «google».«protobuf».«compiler».«CodeGeneratorResponse».«File».«protobuf.internal».«fromMessage»  «wire»  } 

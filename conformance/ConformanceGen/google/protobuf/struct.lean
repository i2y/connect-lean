module

public import Protobuf.Encoding
public import Protobuf.ProtoMessage
public import Protobuf.Base64
public import Protobuf.Reflection
meta import Protobuf.Notation


public section

open Protobuf Encoding
open scoped Protobuf.Notation
enum «google».«protobuf».«NullValue» [  ] {
  «NULL_VALUE» = 0;
}

proto_mutual {
  message «google».«protobuf».«Struct» {
  map<«string», «google».«protobuf».«Value»> «fields» = 1;
}
  oneof «google».«protobuf».«Value».«kind_Type» {
  «google».«protobuf».«NullValue» «null_value» = 1;
  «double» «number_value» = 2;
  «string» «string_value» = 3;
  «bool» «bool_value» = 4;
  «google».«protobuf».«Struct» «struct_value» = 5;
  «google».«protobuf».«ListValue» «list_value» = 6;
}
  message «google».«protobuf».«Value» {
  «google».«protobuf».«Value».«kind_Type» «kind» = 0;
}
  message «google».«protobuf».«ListValue» {
  repeated «google».«protobuf».«Value» «values» = 1;
}
}

 private  initialize  «protobuf.fileDescriptor.676f6f676c652f70726f746f6275662f7374727563742e70726f746f»  :  «Protobuf».«Reflection».«FileDescriptor»  ←  «Protobuf».«Reflection».«generatedPool».«registerFileBase64!»  "Chxnb29nbGUvcHJvdG9idWYvc3RydWN0LnByb3RvEg9nb29nbGUucHJvdG9idWYimAEKBlN0cnVjdBI7CgZmaWVsZHMYASADKAsyIy5nb29nbGUucHJvdG9idWYuU3RydWN0LkZpZWxkc0VudHJ5UgZmaWVsZHMaUQoLRmllbGRzRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSLAoFdmFsdWUYAiABKAsyFi5nb29nbGUucHJvdG9idWYuVmFsdWVSBXZhbHVlOgI4ASKyAgoFVmFsdWUSOwoKbnVsbF92YWx1ZRgBIAEoDjIaLmdvb2dsZS5wcm90b2J1Zi5OdWxsVmFsdWVIAFIJbnVsbFZhbHVlEiMKDG51bWJlcl92YWx1ZRgCIAEoAUgAUgtudW1iZXJWYWx1ZRIjCgxzdHJpbmdfdmFsdWUYAyABKAlIAFILc3RyaW5nVmFsdWUSHwoKYm9vbF92YWx1ZRgEIAEoCEgAUglib29sVmFsdWUSPAoMc3RydWN0X3ZhbHVlGAUgASgLMhcuZ29vZ2xlLnByb3RvYnVmLlN0cnVjdEgAUgtzdHJ1Y3RWYWx1ZRI7CgpsaXN0X3ZhbHVlGAYgASgLMhouZ29vZ2xlLnByb3RvYnVmLkxpc3RWYWx1ZUgAUglsaXN0VmFsdWVCBgoEa2luZCI7CglMaXN0VmFsdWUSLgoGdmFsdWVzGAEgAygLMhYuZ29vZ2xlLnByb3RvYnVmLlZhbHVlUgZ2YWx1ZXMqGwoJTnVsbFZhbHVlEg4KCk5VTExfVkFMVUUQAEJ/ChNjb20uZ29vZ2xlLnByb3RvYnVmQgtTdHJ1Y3RQcm90b1ABWi9nb29nbGUuZ29sYW5nLm9yZy9wcm90b2J1Zi90eXBlcy9rbm93bi9zdHJ1Y3RwYvgBAaICA0dQQqoCHkdvb2dsZS5Qcm90b2J1Zi5XZWxsS25vd25UeXBlc2IGcHJvdG8z" 

 instance  :  «Protobuf».«Reflection».«ReflectEnum»  «google».«protobuf».«NullValue»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«EnumDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "google.protobuf.NullValue"  ,  «toInt32»  :=  «google».«protobuf».«NullValue».«protobuf.internal».«toInt32»  ,  «fromInt32»  :=  «google».«protobuf».«NullValue».«protobuf.internal».«fromInt32»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «google».«protobuf».«Struct»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "google.protobuf.Struct"  ,  «toMessagePartial»  :=  «google».«protobuf».«Struct».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «google».«protobuf».«Struct».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «google».«protobuf».«Value»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "google.protobuf.Value"  ,  «toMessagePartial»  :=  «google».«protobuf».«Value».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «google».«protobuf».«Value».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «google».«protobuf».«ListValue»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "google.protobuf.ListValue"  ,  «toMessagePartial»  :=  «google».«protobuf».«ListValue».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «google».«protobuf».«ListValue».«protobuf.internal».«fromMessage»  «wire»  } 

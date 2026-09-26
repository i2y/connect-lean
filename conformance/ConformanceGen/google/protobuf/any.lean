module

public import Protobuf.Encoding
public import Protobuf.ProtoMessage
public import Protobuf.Base64
public import Protobuf.Reflection
meta import Protobuf.Notation


public section

open Protobuf Encoding
open scoped Protobuf.Notation
message «google».«protobuf».«Any» {
  «string» «type_url» = 1;
  «bytes» «value» = 2;
}

 private  initialize  «protobuf.fileDescriptor.676f6f676c652f70726f746f6275662f616e792e70726f746f»  :  «Protobuf».«Reflection».«FileDescriptor»  ←  «Protobuf».«Reflection».«generatedPool».«registerFileBase64!»  "Chlnb29nbGUvcHJvdG9idWYvYW55LnByb3RvEg9nb29nbGUucHJvdG9idWYiNgoDQW55EhkKCHR5cGVfdXJsGAEgASgJUgd0eXBlVXJsEhQKBXZhbHVlGAIgASgMUgV2YWx1ZUJ2ChNjb20uZ29vZ2xlLnByb3RvYnVmQghBbnlQcm90b1ABWixnb29nbGUuZ29sYW5nLm9yZy9wcm90b2J1Zi90eXBlcy9rbm93bi9hbnlwYqICA0dQQqoCHkdvb2dsZS5Qcm90b2J1Zi5XZWxsS25vd25UeXBlc2IGcHJvdG8z" 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «google».«protobuf».«Any»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "google.protobuf.Any"  ,  «toMessagePartial»  :=  «google».«protobuf».«Any».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «google».«protobuf».«Any».«protobuf.internal».«fromMessage»  «wire»  } 

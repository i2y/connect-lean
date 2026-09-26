module

public import Protobuf.Encoding
public import Protobuf.ProtoMessage
public import Protobuf.Base64
public import Protobuf.Reflection
meta import Protobuf.Notation


public section

open Protobuf Encoding
open scoped Protobuf.Notation
message «edge».«v1».«Ping» {
  «string» «text» = 1;
}

message «edge».«v1».«Pong» {
  «string» «text» = 1;
}

 private  initialize  «protobuf.fileDescriptor.656467652f76312f74797065732e70726f746f»  :  «Protobuf».«Reflection».«FileDescriptor»  ←  «Protobuf».«Reflection».«generatedPool».«registerFileBase64!»  "ChNlZGdlL3YxL3R5cGVzLnByb3RvEgdlZGdlLnYxIhoKBFBpbmcSEgoEdGV4dBgBIAEoCVIEdGV4dCIaCgRQb25nEhIKBHRleHQYASABKAlSBHRleHRiBnByb3RvMw==" 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «edge».«v1».«Ping»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "edge.v1.Ping"  ,  «toMessagePartial»  :=  «edge».«v1».«Ping».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «edge».«v1».«Ping».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «edge».«v1».«Pong»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "edge.v1.Pong"  ,  «toMessagePartial»  :=  «edge».«v1».«Pong».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «edge».«v1».«Pong».«protobuf.internal».«fromMessage»  «wire»  } 

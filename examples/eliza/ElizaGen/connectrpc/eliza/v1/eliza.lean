module

public import Protobuf.Encoding
public import Protobuf.ProtoMessage
public import Protobuf.Base64
public import Protobuf.Reflection
meta import Protobuf.Notation


public section

open Protobuf Encoding
open scoped Protobuf.Notation
message «connectrpc».«eliza».«v1».«SayRequest» {
  «string» «sentence» = 1;
}

message «connectrpc».«eliza».«v1».«SayResponse» {
  «string» «sentence» = 1;
}

message «connectrpc».«eliza».«v1».«ConverseRequest» {
  «string» «sentence» = 1;
}

message «connectrpc».«eliza».«v1».«ConverseResponse» {
  «string» «sentence» = 1;
}

message «connectrpc».«eliza».«v1».«IntroduceRequest» {
  «string» «name» = 1;
}

message «connectrpc».«eliza».«v1».«IntroduceResponse» {
  «string» «sentence» = 1;
}

 private  initialize  «protobuf.fileDescriptor.636f6e6e6563747270632f656c697a612f76312f656c697a612e70726f746f»  :  «Protobuf».«Reflection».«FileDescriptor»  ←  «Protobuf».«Reflection».«generatedPool».«registerFileBase64!»  "Ch9jb25uZWN0cnBjL2VsaXphL3YxL2VsaXphLnByb3RvEhNjb25uZWN0cnBjLmVsaXphLnYxIigKClNheVJlcXVlc3QSGgoIc2VudGVuY2UYASABKAlSCHNlbnRlbmNlIikKC1NheVJlc3BvbnNlEhoKCHNlbnRlbmNlGAEgASgJUghzZW50ZW5jZSItCg9Db252ZXJzZVJlcXVlc3QSGgoIc2VudGVuY2UYASABKAlSCHNlbnRlbmNlIi4KEENvbnZlcnNlUmVzcG9uc2USGgoIc2VudGVuY2UYASABKAlSCHNlbnRlbmNlIiYKEEludHJvZHVjZVJlcXVlc3QSEgoEbmFtZRgBIAEoCVIEbmFtZSIvChFJbnRyb2R1Y2VSZXNwb25zZRIaCghzZW50ZW5jZRgBIAEoCVIIc2VudGVuY2UymAIKDEVsaXphU2VydmljZRJNCgNTYXkSHy5jb25uZWN0cnBjLmVsaXphLnYxLlNheVJlcXVlc3QaIC5jb25uZWN0cnBjLmVsaXphLnYxLlNheVJlc3BvbnNlIgOQAgESWwoIQ29udmVyc2USJC5jb25uZWN0cnBjLmVsaXphLnYxLkNvbnZlcnNlUmVxdWVzdBolLmNvbm5lY3RycGMuZWxpemEudjEuQ29udmVyc2VSZXNwb25zZSgBMAESXAoJSW50cm9kdWNlEiUuY29ubmVjdHJwYy5lbGl6YS52MS5JbnRyb2R1Y2VSZXF1ZXN0GiYuY29ubmVjdHJwYy5lbGl6YS52MS5JbnRyb2R1Y2VSZXNwb25zZTABYgZwcm90bzM=" 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«eliza».«v1».«SayRequest»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.eliza.v1.SayRequest"  ,  «toMessagePartial»  :=  «connectrpc».«eliza».«v1».«SayRequest».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«eliza».«v1».«SayRequest».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«eliza».«v1».«SayResponse»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.eliza.v1.SayResponse"  ,  «toMessagePartial»  :=  «connectrpc».«eliza».«v1».«SayResponse».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«eliza».«v1».«SayResponse».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«eliza».«v1».«ConverseRequest»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.eliza.v1.ConverseRequest"  ,  «toMessagePartial»  :=  «connectrpc».«eliza».«v1».«ConverseRequest».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«eliza».«v1».«ConverseRequest».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«eliza».«v1».«ConverseResponse»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.eliza.v1.ConverseResponse"  ,  «toMessagePartial»  :=  «connectrpc».«eliza».«v1».«ConverseResponse».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«eliza».«v1».«ConverseResponse».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«eliza».«v1».«IntroduceRequest»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.eliza.v1.IntroduceRequest"  ,  «toMessagePartial»  :=  «connectrpc».«eliza».«v1».«IntroduceRequest».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«eliza».«v1».«IntroduceRequest».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«eliza».«v1».«IntroduceResponse»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.eliza.v1.IntroduceResponse"  ,  «toMessagePartial»  :=  «connectrpc».«eliza».«v1».«IntroduceResponse».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«eliza».«v1».«IntroduceResponse».«protobuf.internal».«fromMessage»  «wire»  } 

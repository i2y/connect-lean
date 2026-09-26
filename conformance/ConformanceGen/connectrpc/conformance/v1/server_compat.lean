module

public import Protobuf.Encoding
public import Protobuf.ProtoMessage
public import Protobuf.Base64
public import Protobuf.Reflection
meta import Protobuf.Notation
public import «ConformanceGen».«connectrpc».«conformance».«v1».«config»

public section

open Protobuf Encoding
open scoped Protobuf.Notation
message «connectrpc».«conformance».«v1».«ServerCompatRequest» {
  «connectrpc».«conformance».«v1».«Protocol» «protocol» = 1;
  «connectrpc».«conformance».«v1».«HTTPVersion» «http_version» = 2;
  «bool» «use_tls» = 4;
  «bytes» «client_tls_cert» = 5;
  «uint32» «message_receive_limit» = 6;
  «connectrpc».«conformance».«v1».«TLSCreds» «server_creds» = 7;
}

message «connectrpc».«conformance».«v1».«ServerCompatResponse» {
  «string» «host» = 1;
  «uint32» «port» = 2;
  «bytes» «pem_cert» = 3;
}

 private  initialize  «protobuf.fileDescriptor.636f6e6e6563747270632f636f6e666f726d616e63652f76312f7365727665725f636f6d7061742e70726f746f»  :  «Protobuf».«Reflection».«FileDescriptor»  ←  «Protobuf».«Reflection».«generatedPool».«registerFileBase64!»  "Ci1jb25uZWN0cnBjL2NvbmZvcm1hbmNlL3YxL3NlcnZlcl9jb21wYXQucHJvdG8SGWNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEaJmNvbm5lY3RycGMvY29uZm9ybWFuY2UvdjEvY29uZmlnLnByb3RvIt4CChNTZXJ2ZXJDb21wYXRSZXF1ZXN0Ej8KCHByb3RvY29sGAEgASgOMiMuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5Qcm90b2NvbFIIcHJvdG9jb2wSSQoMaHR0cF92ZXJzaW9uGAIgASgOMiYuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5IVFRQVmVyc2lvblILaHR0cFZlcnNpb24SFwoHdXNlX3RscxgEIAEoCFIGdXNlVGxzEiYKD2NsaWVudF90bHNfY2VydBgFIAEoDFINY2xpZW50VGxzQ2VydBIyChVtZXNzYWdlX3JlY2VpdmVfbGltaXQYBiABKA1SE21lc3NhZ2VSZWNlaXZlTGltaXQSRgoMc2VydmVyX2NyZWRzGAcgASgLMiMuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5UTFNDcmVkc1ILc2VydmVyQ3JlZHMiWQoUU2VydmVyQ29tcGF0UmVzcG9uc2USEgoEaG9zdBgBIAEoCVIEaG9zdBISCgRwb3J0GAIgASgNUgRwb3J0EhkKCHBlbV9jZXJ0GAMgASgMUgdwZW1DZXJ0YgZwcm90bzM=" 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ServerCompatRequest»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ServerCompatRequest"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ServerCompatRequest».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ServerCompatRequest».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ServerCompatResponse»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ServerCompatResponse"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ServerCompatResponse».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ServerCompatResponse».«protobuf.internal».«fromMessage»  «wire»  } 

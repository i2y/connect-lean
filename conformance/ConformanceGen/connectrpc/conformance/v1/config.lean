module

public import Protobuf.Encoding
public import Protobuf.ProtoMessage
public import Protobuf.Base64
public import Protobuf.Reflection
meta import Protobuf.Notation


public section

open Protobuf Encoding
open scoped Protobuf.Notation
enum «connectrpc».«conformance».«v1».«HTTPVersion» [  ] {
  «HTTP_VERSION_UNSPECIFIED» = 0;
  «HTTP_VERSION_1» = 1;
  «HTTP_VERSION_2» = 2;
  «HTTP_VERSION_3» = 3;
}

enum «connectrpc».«conformance».«v1».«Protocol» [  ] {
  «PROTOCOL_UNSPECIFIED» = 0;
  «PROTOCOL_CONNECT» = 1;
  «PROTOCOL_GRPC» = 2;
  «PROTOCOL_GRPC_WEB» = 3;
}

enum «connectrpc».«conformance».«v1».«Codec» [  ] {
  «CODEC_UNSPECIFIED» = 0;
  «CODEC_PROTO» = 1;
  «CODEC_JSON» = 2;
  «CODEC_TEXT» = 3;
}


enum «connectrpc».«conformance».«v1».«Compression» [  ] {
  «COMPRESSION_UNSPECIFIED» = 0;
  «COMPRESSION_IDENTITY» = 1;
  «COMPRESSION_GZIP» = 2;
  «COMPRESSION_BR» = 3;
  «COMPRESSION_ZSTD» = 4;
  «COMPRESSION_DEFLATE» = 5;
  «COMPRESSION_SNAPPY» = 6;
}

enum «connectrpc».«conformance».«v1».«StreamType» [  ] {
  «STREAM_TYPE_UNSPECIFIED» = 0;
  «STREAM_TYPE_UNARY» = 1;
  «STREAM_TYPE_CLIENT_STREAM» = 2;
  «STREAM_TYPE_SERVER_STREAM» = 3;
  «STREAM_TYPE_HALF_DUPLEX_BIDI_STREAM» = 4;
  «STREAM_TYPE_FULL_DUPLEX_BIDI_STREAM» = 5;
}

enum «connectrpc».«conformance».«v1».«Code» [  ] {
  «CODE_UNSPECIFIED» = 0;
  «CODE_CANCELED» = 1;
  «CODE_UNKNOWN» = 2;
  «CODE_INVALID_ARGUMENT» = 3;
  «CODE_DEADLINE_EXCEEDED» = 4;
  «CODE_NOT_FOUND» = 5;
  «CODE_ALREADY_EXISTS» = 6;
  «CODE_PERMISSION_DENIED» = 7;
  «CODE_RESOURCE_EXHAUSTED» = 8;
  «CODE_FAILED_PRECONDITION» = 9;
  «CODE_ABORTED» = 10;
  «CODE_OUT_OF_RANGE» = 11;
  «CODE_UNIMPLEMENTED» = 12;
  «CODE_INTERNAL» = 13;
  «CODE_UNAVAILABLE» = 14;
  «CODE_DATA_LOSS» = 15;
  «CODE_UNAUTHENTICATED» = 16;
}

message «connectrpc».«conformance».«v1».«Features» {
  repeated «connectrpc».«conformance».«v1».«HTTPVersion» «versions» = 1 [ «packed» = true ];
  repeated «connectrpc».«conformance».«v1».«Protocol» «protocols» = 2 [ «packed» = true ];
  repeated «connectrpc».«conformance».«v1».«Codec» «codecs» = 3 [ «packed» = true ];
  repeated «connectrpc».«conformance».«v1».«Compression» «compressions» = 4 [ «packed» = true ];
  repeated «connectrpc».«conformance».«v1».«StreamType» «stream_types» = 5 [ «packed» = true ];
  optional «bool» «supports_h2c» = 6;
  optional «bool» «supports_tls» = 7;
  optional «bool» «supports_tls_client_certs» = 8;
  optional «bool» «supports_trailers» = 9;
  optional «bool» «supports_half_duplex_bidi_over_http1» = 10;
  optional «bool» «supports_connect_get» = 11;
  optional «bool» «supports_message_receive_limit» = 12;
}

message «connectrpc».«conformance».«v1».«ConfigCase» {
  «connectrpc».«conformance».«v1».«HTTPVersion» «version» = 1;
  «connectrpc».«conformance».«v1».«Protocol» «protocol» = 2;
  «connectrpc».«conformance».«v1».«Codec» «codec» = 3;
  «connectrpc».«conformance».«v1».«Compression» «compression» = 4;
  «connectrpc».«conformance».«v1».«StreamType» «stream_type» = 5;
  optional «bool» «use_tls» = 6;
  optional «bool» «use_tls_client_certs» = 7;
  optional «bool» «use_message_receive_limit» = 8;
}

message «connectrpc».«conformance».«v1».«Config» {
  «connectrpc».«conformance».«v1».«Features» «features» = 1;
  repeated «connectrpc».«conformance».«v1».«ConfigCase» «include_cases» = 2;
  repeated «connectrpc».«conformance».«v1».«ConfigCase» «exclude_cases» = 3;
}

message «connectrpc».«conformance».«v1».«TLSCreds» {
  «bytes» «cert» = 1;
  «bytes» «key» = 2;
}

 private  initialize  «protobuf.fileDescriptor.636f6e6e6563747270632f636f6e666f726d616e63652f76312f636f6e6669672e70726f746f»  :  «Protobuf».«Reflection».«FileDescriptor»  ←  «Protobuf».«Reflection».«generatedPool».«registerFileBase64!»  "CiZjb25uZWN0cnBjL2NvbmZvcm1hbmNlL3YxL2NvbmZpZy5wcm90bxIZY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MSLhAQoGQ29uZmlnEj8KCGZlYXR1cmVzGAEgASgLMiMuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5GZWF0dXJlc1IIZmVhdHVyZXMSSgoNaW5jbHVkZV9jYXNlcxgCIAMoCzIlLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuQ29uZmlnQ2FzZVIMaW5jbHVkZUNhc2VzEkoKDWV4Y2x1ZGVfY2FzZXMYAyADKAsyJS5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkNvbmZpZ0Nhc2VSDGV4Y2x1ZGVDYXNlcyKzBwoIRmVhdHVyZXMSQgoIdmVyc2lvbnMYASADKA4yJi5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkhUVFBWZXJzaW9uUgh2ZXJzaW9ucxJBCglwcm90b2NvbHMYAiADKA4yIy5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLlByb3RvY29sUglwcm90b2NvbHMSOAoGY29kZWNzGAMgAygOMiAuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5Db2RlY1IGY29kZWNzEkoKDGNvbXByZXNzaW9ucxgEIAMoDjImLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuQ29tcHJlc3Npb25SDGNvbXByZXNzaW9ucxJICgxzdHJlYW1fdHlwZXMYBSADKA4yJS5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLlN0cmVhbVR5cGVSC3N0cmVhbVR5cGVzEiYKDHN1cHBvcnRzX2gyYxgGIAEoCEgAUgtzdXBwb3J0c0gyY4gBARImCgxzdXBwb3J0c190bHMYByABKAhIAVILc3VwcG9ydHNUbHOIAQESPgoZc3VwcG9ydHNfdGxzX2NsaWVudF9jZXJ0cxgIIAEoCEgCUhZzdXBwb3J0c1Rsc0NsaWVudENlcnRziAEBEjAKEXN1cHBvcnRzX3RyYWlsZXJzGAkgASgISANSEHN1cHBvcnRzVHJhaWxlcnOIAQESUgokc3VwcG9ydHNfaGFsZl9kdXBsZXhfYmlkaV9vdmVyX2h0dHAxGAogASgISARSH3N1cHBvcnRzSGFsZkR1cGxleEJpZGlPdmVySHR0cDGIAQESNQoUc3VwcG9ydHNfY29ubmVjdF9nZXQYCyABKAhIBVISc3VwcG9ydHNDb25uZWN0R2V0iAEBEkgKHnN1cHBvcnRzX21lc3NhZ2VfcmVjZWl2ZV9saW1pdBgMIAEoCEgGUhtzdXBwb3J0c01lc3NhZ2VSZWNlaXZlTGltaXSIAQFCDwoNX3N1cHBvcnRzX2gyY0IPCg1fc3VwcG9ydHNfdGxzQhwKGl9zdXBwb3J0c190bHNfY2xpZW50X2NlcnRzQhQKEl9zdXBwb3J0c190cmFpbGVyc0InCiVfc3VwcG9ydHNfaGFsZl9kdXBsZXhfYmlkaV9vdmVyX2h0dHAxQhcKFV9zdXBwb3J0c19jb25uZWN0X2dldEIhCh9fc3VwcG9ydHNfbWVzc2FnZV9yZWNlaXZlX2xpbWl0IrAECgpDb25maWdDYXNlEkAKB3ZlcnNpb24YASABKA4yJi5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkhUVFBWZXJzaW9uUgd2ZXJzaW9uEj8KCHByb3RvY29sGAIgASgOMiMuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5Qcm90b2NvbFIIcHJvdG9jb2wSNgoFY29kZWMYAyABKA4yIC5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkNvZGVjUgVjb2RlYxJICgtjb21wcmVzc2lvbhgEIAEoDjImLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuQ29tcHJlc3Npb25SC2NvbXByZXNzaW9uEkYKC3N0cmVhbV90eXBlGAUgASgOMiUuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5TdHJlYW1UeXBlUgpzdHJlYW1UeXBlEhwKB3VzZV90bHMYBiABKAhIAFIGdXNlVGxziAEBEjQKFHVzZV90bHNfY2xpZW50X2NlcnRzGAcgASgISAFSEXVzZVRsc0NsaWVudENlcnRziAEBEj4KGXVzZV9tZXNzYWdlX3JlY2VpdmVfbGltaXQYCCABKAhIAlIWdXNlTWVzc2FnZVJlY2VpdmVMaW1pdIgBAUIKCghfdXNlX3Rsc0IXChVfdXNlX3Rsc19jbGllbnRfY2VydHNCHAoaX3VzZV9tZXNzYWdlX3JlY2VpdmVfbGltaXQiMAoIVExTQ3JlZHMSEgoEY2VydBgBIAEoDFIEY2VydBIQCgNrZXkYAiABKAxSA2tleSpnCgtIVFRQVmVyc2lvbhIcChhIVFRQX1ZFUlNJT05fVU5TUEVDSUZJRUQQABISCg5IVFRQX1ZFUlNJT05fMRABEhIKDkhUVFBfVkVSU0lPTl8yEAISEgoOSFRUUF9WRVJTSU9OXzMQAypkCghQcm90b2NvbBIYChRQUk9UT0NPTF9VTlNQRUNJRklFRBAAEhQKEFBST1RPQ09MX0NPTk5FQ1QQARIRCg1QUk9UT0NPTF9HUlBDEAISFQoRUFJPVE9DT0xfR1JQQ19XRUIQAypTCgVDb2RlYxIVChFDT0RFQ19VTlNQRUNJRklFRBAAEg8KC0NPREVDX1BST1RPEAESDgoKQ09ERUNfSlNPThACEhIKCkNPREVDX1RFWFQQAxoCCAEqtQEKC0NvbXByZXNzaW9uEhsKF0NPTVBSRVNTSU9OX1VOU1BFQ0lGSUVEEAASGAoUQ09NUFJFU1NJT05fSURFTlRJVFkQARIUChBDT01QUkVTU0lPTl9HWklQEAISEgoOQ09NUFJFU1NJT05fQlIQAxIUChBDT01QUkVTU0lPTl9aU1REEAQSFwoTQ09NUFJFU1NJT05fREVGTEFURRAFEhYKEkNPTVBSRVNTSU9OX1NOQVBQWRAGKtABCgpTdHJlYW1UeXBlEhsKF1NUUkVBTV9UWVBFX1VOU1BFQ0lGSUVEEAASFQoRU1RSRUFNX1RZUEVfVU5BUlkQARIdChlTVFJFQU1fVFlQRV9DTElFTlRfU1RSRUFNEAISHQoZU1RSRUFNX1RZUEVfU0VSVkVSX1NUUkVBTRADEicKI1NUUkVBTV9UWVBFX0hBTEZfRFVQTEVYX0JJRElfU1RSRUFNEAQSJwojU1RSRUFNX1RZUEVfRlVMTF9EVVBMRVhfQklESV9TVFJFQU0QBSqUAwoEQ29kZRIUChBDT0RFX1VOU1BFQ0lGSUVEEAASEQoNQ09ERV9DQU5DRUxFRBABEhAKDENPREVfVU5LTk9XThACEhkKFUNPREVfSU5WQUxJRF9BUkdVTUVOVBADEhoKFkNPREVfREVBRExJTkVfRVhDRUVERUQQBBISCg5DT0RFX05PVF9GT1VORBAFEhcKE0NPREVfQUxSRUFEWV9FWElTVFMQBhIaChZDT0RFX1BFUk1JU1NJT05fREVOSUVEEAcSGwoXQ09ERV9SRVNPVVJDRV9FWEhBVVNURUQQCBIcChhDT0RFX0ZBSUxFRF9QUkVDT05ESVRJT04QCRIQCgxDT0RFX0FCT1JURUQQChIVChFDT0RFX09VVF9PRl9SQU5HRRALEhYKEkNPREVfVU5JTVBMRU1FTlRFRBAMEhEKDUNPREVfSU5URVJOQUwQDRIUChBDT0RFX1VOQVZBSUxBQkxFEA4SEgoOQ09ERV9EQVRBX0xPU1MQDxIYChRDT0RFX1VOQVVUSEVOVElDQVRFRBAQYgZwcm90bzM=" 

 instance  :  «Protobuf».«Reflection».«ReflectEnum»  «connectrpc».«conformance».«v1».«HTTPVersion»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«EnumDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.HTTPVersion"  ,  «toInt32»  :=  «connectrpc».«conformance».«v1».«HTTPVersion».«protobuf.internal».«toInt32»  ,  «fromInt32»  :=  «connectrpc».«conformance».«v1».«HTTPVersion».«protobuf.internal».«fromInt32»  } 

 instance  :  «Protobuf».«Reflection».«ReflectEnum»  «connectrpc».«conformance».«v1».«Protocol»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«EnumDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.Protocol"  ,  «toInt32»  :=  «connectrpc».«conformance».«v1».«Protocol».«protobuf.internal».«toInt32»  ,  «fromInt32»  :=  «connectrpc».«conformance».«v1».«Protocol».«protobuf.internal».«fromInt32»  } 

 instance  :  «Protobuf».«Reflection».«ReflectEnum»  «connectrpc».«conformance».«v1».«Codec»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«EnumDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.Codec"  ,  «toInt32»  :=  «connectrpc».«conformance».«v1».«Codec».«protobuf.internal».«toInt32»  ,  «fromInt32»  :=  «connectrpc».«conformance».«v1».«Codec».«protobuf.internal».«fromInt32»  } 

 instance  :  «Protobuf».«Reflection».«ReflectEnum»  «connectrpc».«conformance».«v1».«Compression»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«EnumDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.Compression"  ,  «toInt32»  :=  «connectrpc».«conformance».«v1».«Compression».«protobuf.internal».«toInt32»  ,  «fromInt32»  :=  «connectrpc».«conformance».«v1».«Compression».«protobuf.internal».«fromInt32»  } 

 instance  :  «Protobuf».«Reflection».«ReflectEnum»  «connectrpc».«conformance».«v1».«StreamType»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«EnumDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.StreamType"  ,  «toInt32»  :=  «connectrpc».«conformance».«v1».«StreamType».«protobuf.internal».«toInt32»  ,  «fromInt32»  :=  «connectrpc».«conformance».«v1».«StreamType».«protobuf.internal».«fromInt32»  } 

 instance  :  «Protobuf».«Reflection».«ReflectEnum»  «connectrpc».«conformance».«v1».«Code»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«EnumDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.Code"  ,  «toInt32»  :=  «connectrpc».«conformance».«v1».«Code».«protobuf.internal».«toInt32»  ,  «fromInt32»  :=  «connectrpc».«conformance».«v1».«Code».«protobuf.internal».«fromInt32»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«Config»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.Config"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«Config».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«Config».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«Features»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.Features"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«Features».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«Features».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ConfigCase»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ConfigCase"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ConfigCase».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ConfigCase».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«TLSCreds»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.TLSCreds"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«TLSCreds».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«TLSCreds».«protobuf.internal».«fromMessage»  «wire»  } 

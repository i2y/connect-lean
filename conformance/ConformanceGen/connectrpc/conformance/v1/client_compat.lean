module

public import Protobuf.Encoding
public import Protobuf.ProtoMessage
public import Protobuf.Base64
public import Protobuf.Reflection
meta import Protobuf.Notation
public import «ConformanceGen».«connectrpc».«conformance».«v1».«config»
public import «ConformanceGen».«connectrpc».«conformance».«v1».«service»
public import «ConformanceGen».«google».«protobuf».«any»
public import «ConformanceGen».«google».«protobuf».«empty»
public import «ConformanceGen».«google».«protobuf».«struct»

public section

open Protobuf Encoding
open scoped Protobuf.Notation
oneof «connectrpc».«conformance».«v1».«ClientCompatRequest».«Cancel».«cancel_timing_Type» {
  «google».«protobuf».«Empty» «before_close_send» = 1;
  «uint32» «after_close_send_ms» = 2;
  «uint32» «after_num_responses» = 3;
}

message «connectrpc».«conformance».«v1».«ClientCompatRequest».«Cancel» {
  «connectrpc».«conformance».«v1».«ClientCompatRequest».«Cancel».«cancel_timing_Type» «cancel_timing» = 0;
}

message «connectrpc».«conformance».«v1».«ClientCompatRequest» {
  «string» «test_name» = 1;
  «connectrpc».«conformance».«v1».«HTTPVersion» «http_version» = 2;
  «connectrpc».«conformance».«v1».«Protocol» «protocol» = 3;
  «connectrpc».«conformance».«v1».«Codec» «codec» = 4;
  «connectrpc».«conformance».«v1».«Compression» «compression» = 5;
  «string» «host» = 6;
  «uint32» «port» = 7;
  «bytes» «server_tls_cert» = 8;
  «connectrpc».«conformance».«v1».«TLSCreds» «client_tls_creds» = 9;
  «uint32» «message_receive_limit» = 10;
  optional «string» «service» = 11;
  optional «string» «method» = 12;
  «connectrpc».«conformance».«v1».«StreamType» «stream_type» = 13;
  «bool» «use_get_http_method» = 14;
  repeated «connectrpc».«conformance».«v1».«Header» «request_headers» = 15;
  repeated «google».«protobuf».«Any» «request_messages» = 16;
  optional «uint32» «timeout_ms» = 17;
  «uint32» «request_delay_ms» = 18;
  «connectrpc».«conformance».«v1».«ClientCompatRequest».«Cancel» «cancel» = 19;
  «connectrpc».«conformance».«v1».«RawHTTPRequest» «raw_request» = 20;
}

message «connectrpc».«conformance».«v1».«ClientResponseResult» {
  repeated «connectrpc».«conformance».«v1».«Header» «response_headers» = 1;
  repeated «connectrpc».«conformance».«v1».«ConformancePayload» «payloads» = 2;
  «connectrpc».«conformance».«v1».«Error» «error» = 3;
  repeated «connectrpc».«conformance».«v1».«Header» «response_trailers» = 4;
  «int32» «num_unsent_requests» = 5;
  optional «int32» «http_status_code» = 6;
  repeated «string» «feedback» = 7;
}

message «connectrpc».«conformance».«v1».«ClientErrorResult» {
  «string» «message» = 1;
}

oneof «connectrpc».«conformance».«v1».«ClientCompatResponse».«result_Type» {
  «connectrpc».«conformance».«v1».«ClientResponseResult» «response» = 2;
  «connectrpc».«conformance».«v1».«ClientErrorResult» «error» = 3;
}

message «connectrpc».«conformance».«v1».«ClientCompatResponse» {
  «string» «test_name» = 1;
  «connectrpc».«conformance».«v1».«ClientCompatResponse».«result_Type» «result» = 0;
}

message «connectrpc».«conformance».«v1».«WireDetails» {
  «int32» «actual_status_code» = 1;
  «google».«protobuf».«Struct» «connect_error_raw» = 2;
  repeated «connectrpc».«conformance».«v1».«Header» «actual_http_trailers» = 3;
  optional «string» «actual_grpcweb_trailers» = 4;
}

 private  initialize  «protobuf.fileDescriptor.636f6e6e6563747270632f636f6e666f726d616e63652f76312f636c69656e745f636f6d7061742e70726f746f»  :  «Protobuf».«Reflection».«FileDescriptor»  ←  «Protobuf».«Reflection».«generatedPool».«registerFileBase64!»  "Ci1jb25uZWN0cnBjL2NvbmZvcm1hbmNlL3YxL2NsaWVudF9jb21wYXQucHJvdG8SGWNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEaJmNvbm5lY3RycGMvY29uZm9ybWFuY2UvdjEvY29uZmlnLnByb3RvGidjb25uZWN0cnBjL2NvbmZvcm1hbmNlL3YxL3NlcnZpY2UucHJvdG8aGWdvb2dsZS9wcm90b2J1Zi9hbnkucHJvdG8aG2dvb2dsZS9wcm90b2J1Zi9lbXB0eS5wcm90bxocZ29vZ2xlL3Byb3RvYnVmL3N0cnVjdC5wcm90byKnCgoTQ2xpZW50Q29tcGF0UmVxdWVzdBIbCgl0ZXN0X25hbWUYASABKAlSCHRlc3ROYW1lEkkKDGh0dHBfdmVyc2lvbhgCIAEoDjImLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuSFRUUFZlcnNpb25SC2h0dHBWZXJzaW9uEj8KCHByb3RvY29sGAMgASgOMiMuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5Qcm90b2NvbFIIcHJvdG9jb2wSNgoFY29kZWMYBCABKA4yIC5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkNvZGVjUgVjb2RlYxJICgtjb21wcmVzc2lvbhgFIAEoDjImLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuQ29tcHJlc3Npb25SC2NvbXByZXNzaW9uEhIKBGhvc3QYBiABKAlSBGhvc3QSEgoEcG9ydBgHIAEoDVIEcG9ydBImCg9zZXJ2ZXJfdGxzX2NlcnQYCCABKAxSDXNlcnZlclRsc0NlcnQSTQoQY2xpZW50X3Rsc19jcmVkcxgJIAEoCzIjLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuVExTQ3JlZHNSDmNsaWVudFRsc0NyZWRzEjIKFW1lc3NhZ2VfcmVjZWl2ZV9saW1pdBgKIAEoDVITbWVzc2FnZVJlY2VpdmVMaW1pdBIdCgdzZXJ2aWNlGAsgASgJSABSB3NlcnZpY2WIAQESGwoGbWV0aG9kGAwgASgJSAFSBm1ldGhvZIgBARJGCgtzdHJlYW1fdHlwZRgNIAEoDjIlLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuU3RyZWFtVHlwZVIKc3RyZWFtVHlwZRItChN1c2VfZ2V0X2h0dHBfbWV0aG9kGA4gASgIUhB1c2VHZXRIdHRwTWV0aG9kEkoKD3JlcXVlc3RfaGVhZGVycxgPIAMoCzIhLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuSGVhZGVyUg5yZXF1ZXN0SGVhZGVycxI/ChByZXF1ZXN0X21lc3NhZ2VzGBAgAygLMhQuZ29vZ2xlLnByb3RvYnVmLkFueVIPcmVxdWVzdE1lc3NhZ2VzEiIKCnRpbWVvdXRfbXMYESABKA1IAlIJdGltZW91dE1ziAEBEigKEHJlcXVlc3RfZGVsYXlfbXMYEiABKA1SDnJlcXVlc3REZWxheU1zEk0KBmNhbmNlbBgTIAEoCzI1LmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuQ2xpZW50Q29tcGF0UmVxdWVzdC5DYW5jZWxSBmNhbmNlbBJKCgtyYXdfcmVxdWVzdBgUIAEoCzIpLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuUmF3SFRUUFJlcXVlc3RSCnJhd1JlcXVlc3QawgEKBkNhbmNlbBJEChFiZWZvcmVfY2xvc2Vfc2VuZBgBIAEoCzIWLmdvb2dsZS5wcm90b2J1Zi5FbXB0eUgAUg9iZWZvcmVDbG9zZVNlbmQSLwoTYWZ0ZXJfY2xvc2Vfc2VuZF9tcxgCIAEoDUgAUhBhZnRlckNsb3NlU2VuZE1zEjAKE2FmdGVyX251bV9yZXNwb25zZXMYAyABKA1IAFIRYWZ0ZXJOdW1SZXNwb25zZXNCDwoNY2FuY2VsX3RpbWluZ0IKCghfc2VydmljZUIJCgdfbWV0aG9kQg0KC190aW1lb3V0X21zItIBChRDbGllbnRDb21wYXRSZXNwb25zZRIbCgl0ZXN0X25hbWUYASABKAlSCHRlc3ROYW1lEk0KCHJlc3BvbnNlGAIgASgLMi8uY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5DbGllbnRSZXNwb25zZVJlc3VsdEgAUghyZXNwb25zZRJECgVlcnJvchgDIAEoCzIsLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuQ2xpZW50RXJyb3JSZXN1bHRIAFIFZXJyb3JCCAoGcmVzdWx0IscDChRDbGllbnRSZXNwb25zZVJlc3VsdBJMChByZXNwb25zZV9oZWFkZXJzGAEgAygLMiEuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5IZWFkZXJSD3Jlc3BvbnNlSGVhZGVycxJJCghwYXlsb2FkcxgCIAMoCzItLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuQ29uZm9ybWFuY2VQYXlsb2FkUghwYXlsb2FkcxI2CgVlcnJvchgDIAEoCzIgLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuRXJyb3JSBWVycm9yEk4KEXJlc3BvbnNlX3RyYWlsZXJzGAQgAygLMiEuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5IZWFkZXJSEHJlc3BvbnNlVHJhaWxlcnMSLgoTbnVtX3Vuc2VudF9yZXF1ZXN0cxgFIAEoBVIRbnVtVW5zZW50UmVxdWVzdHMSLQoQaHR0cF9zdGF0dXNfY29kZRgGIAEoBUgAUg5odHRwU3RhdHVzQ29kZYgBARIaCghmZWVkYmFjaxgHIAMoCVIIZmVlZGJhY2tCEwoRX2h0dHBfc3RhdHVzX2NvZGUiLQoRQ2xpZW50RXJyb3JSZXN1bHQSGAoHbWVzc2FnZRgBIAEoCVIHbWVzc2FnZSKuAgoLV2lyZURldGFpbHMSLAoSYWN0dWFsX3N0YXR1c19jb2RlGAEgASgFUhBhY3R1YWxTdGF0dXNDb2RlEkMKEWNvbm5lY3RfZXJyb3JfcmF3GAIgASgLMhcuZ29vZ2xlLnByb3RvYnVmLlN0cnVjdFIPY29ubmVjdEVycm9yUmF3ElMKFGFjdHVhbF9odHRwX3RyYWlsZXJzGAMgAygLMiEuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5IZWFkZXJSEmFjdHVhbEh0dHBUcmFpbGVycxI7ChdhY3R1YWxfZ3JwY3dlYl90cmFpbGVycxgEIAEoCUgAUhVhY3R1YWxHcnBjd2ViVHJhaWxlcnOIAQFCGgoYX2FjdHVhbF9ncnBjd2ViX3RyYWlsZXJzYgZwcm90bzM=" 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ClientCompatRequest»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ClientCompatRequest"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ClientCompatRequest».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ClientCompatRequest».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ClientCompatRequest».«Cancel»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ClientCompatRequest.Cancel"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ClientCompatRequest».«Cancel».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ClientCompatRequest».«Cancel».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ClientCompatResponse»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ClientCompatResponse"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ClientCompatResponse».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ClientCompatResponse».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ClientResponseResult»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ClientResponseResult"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ClientResponseResult».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ClientResponseResult».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ClientErrorResult»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ClientErrorResult"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ClientErrorResult».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ClientErrorResult».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«WireDetails»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.WireDetails"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«WireDetails».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«WireDetails».«protobuf.internal».«fromMessage»  «wire»  } 

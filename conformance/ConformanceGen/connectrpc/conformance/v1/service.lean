module

public import Protobuf.Encoding
public import Protobuf.ProtoMessage
public import Protobuf.Base64
public import Protobuf.Reflection
meta import Protobuf.Notation
public import «ConformanceGen».«connectrpc».«conformance».«v1».«config»
public import «ConformanceGen».«google».«protobuf».«any»

public section

open Protobuf Encoding
open scoped Protobuf.Notation
message «connectrpc».«conformance».«v1».«Header» {
  «string» «name» = 1;
  repeated «string» «value» = 2;
}

oneof «connectrpc».«conformance».«v1».«MessageContents».«data_Type» {
  «bytes» «binary» = 1;
  «string» «text» = 2;
  «google».«protobuf».«Any» «binary_message» = 3;
}

message «connectrpc».«conformance».«v1».«MessageContents» {
  «connectrpc».«conformance».«v1».«Compression» «compression» = 4;
  «connectrpc».«conformance».«v1».«MessageContents».«data_Type» «data» = 0;
}

message «connectrpc».«conformance».«v1».«StreamContents».«StreamItem» {
  «uint32» «flags» = 1;
  optional «uint32» «length» = 2;
  «connectrpc».«conformance».«v1».«MessageContents» «payload» = 3;
}

message «connectrpc».«conformance».«v1».«StreamContents» {
  repeated «connectrpc».«conformance».«v1».«StreamContents».«StreamItem» «items» = 1;
}

oneof «connectrpc».«conformance».«v1».«RawHTTPResponse».«body_Type» {
  «connectrpc».«conformance».«v1».«MessageContents» «unary» = 3;
  «connectrpc».«conformance».«v1».«StreamContents» «stream» = 4;
}

message «connectrpc».«conformance».«v1».«RawHTTPResponse» {
  «uint32» «status_code» = 1;
  repeated «connectrpc».«conformance».«v1».«Header» «headers» = 2;
  repeated «connectrpc».«conformance».«v1».«Header» «trailers» = 5;
  «connectrpc».«conformance».«v1».«RawHTTPResponse».«body_Type» «body» = 0;
}

message «connectrpc».«conformance».«v1».«Error» {
  «connectrpc».«conformance».«v1».«Code» «code» = 1;
  optional «string» «message» = 2;
  repeated «google».«protobuf».«Any» «details» = 3;
}

oneof «connectrpc».«conformance».«v1».«UnaryResponseDefinition».«response_Type» {
  «bytes» «response_data» = 2;
  «connectrpc».«conformance».«v1».«Error» «error» = 3;
}

message «connectrpc».«conformance».«v1».«UnaryResponseDefinition» {
  repeated «connectrpc».«conformance».«v1».«Header» «response_headers» = 1;
  repeated «connectrpc».«conformance».«v1».«Header» «response_trailers» = 4;
  «uint32» «response_delay_ms» = 6;
  «connectrpc».«conformance».«v1».«RawHTTPResponse» «raw_response» = 5;
  «connectrpc».«conformance».«v1».«UnaryResponseDefinition».«response_Type» «response» = 0;
}

message «connectrpc».«conformance».«v1».«StreamResponseDefinition» {
  repeated «connectrpc».«conformance».«v1».«Header» «response_headers» = 1;
  repeated «bytes» «response_data» = 2;
  «uint32» «response_delay_ms» = 3;
  «connectrpc».«conformance».«v1».«Error» «error» = 4;
  repeated «connectrpc».«conformance».«v1».«Header» «response_trailers» = 5;
  «connectrpc».«conformance».«v1».«RawHTTPResponse» «raw_response» = 6;
}

message «connectrpc».«conformance».«v1».«UnaryRequest» {
  «connectrpc».«conformance».«v1».«UnaryResponseDefinition» «response_definition» = 1;
  «bytes» «request_data» = 2;
}

message «connectrpc».«conformance».«v1».«ConformancePayload».«ConnectGetInfo» {
  repeated «connectrpc».«conformance».«v1».«Header» «query_params» = 1;
}

message «connectrpc».«conformance».«v1».«ConformancePayload».«RequestInfo» {
  repeated «connectrpc».«conformance».«v1».«Header» «request_headers» = 1;
  optional «int64» «timeout_ms» = 2;
  repeated «google».«protobuf».«Any» «requests» = 3;
  «connectrpc».«conformance».«v1».«ConformancePayload».«ConnectGetInfo» «connect_get_info» = 4;
}

message «connectrpc».«conformance».«v1».«ConformancePayload» {
  «bytes» «data» = 1;
  «connectrpc».«conformance».«v1».«ConformancePayload».«RequestInfo» «request_info» = 2;
}

message «connectrpc».«conformance».«v1».«UnaryResponse» {
  «connectrpc».«conformance».«v1».«ConformancePayload» «payload» = 1;
}

message «connectrpc».«conformance».«v1».«IdempotentUnaryRequest» {
  «connectrpc».«conformance».«v1».«UnaryResponseDefinition» «response_definition» = 1;
  «bytes» «request_data» = 2;
}

message «connectrpc».«conformance».«v1».«IdempotentUnaryResponse» {
  «connectrpc».«conformance».«v1».«ConformancePayload» «payload» = 1;
}

message «connectrpc».«conformance».«v1».«ServerStreamRequest» {
  «connectrpc».«conformance».«v1».«StreamResponseDefinition» «response_definition» = 1;
  «bytes» «request_data» = 2;
}

message «connectrpc».«conformance».«v1».«ServerStreamResponse» {
  «connectrpc».«conformance».«v1».«ConformancePayload» «payload» = 1;
}

message «connectrpc».«conformance».«v1».«ClientStreamRequest» {
  «connectrpc».«conformance».«v1».«UnaryResponseDefinition» «response_definition» = 1;
  «bytes» «request_data» = 2;
}

message «connectrpc».«conformance».«v1».«ClientStreamResponse» {
  «connectrpc».«conformance».«v1».«ConformancePayload» «payload» = 1;
}

message «connectrpc».«conformance».«v1».«BidiStreamRequest» {
  «connectrpc».«conformance».«v1».«StreamResponseDefinition» «response_definition» = 1;
  «bool» «full_duplex» = 2;
  «bytes» «request_data» = 3;
}

message «connectrpc».«conformance».«v1».«BidiStreamResponse» {
  «connectrpc».«conformance».«v1».«ConformancePayload» «payload» = 1;
}

message «connectrpc».«conformance».«v1».«UnimplementedRequest» {}

message «connectrpc».«conformance».«v1».«UnimplementedResponse» {}

message «connectrpc».«conformance».«v1».«RawHTTPRequest».«EncodedQueryParam» {
  «string» «name» = 1;
  «connectrpc».«conformance».«v1».«MessageContents» «value» = 2;
  «bool» «base64_encode» = 3;
}

oneof «connectrpc».«conformance».«v1».«RawHTTPRequest».«body_Type» {
  «connectrpc».«conformance».«v1».«MessageContents» «unary» = 6;
  «connectrpc».«conformance».«v1».«StreamContents» «stream» = 7;
}

message «connectrpc».«conformance».«v1».«RawHTTPRequest» {
  «string» «verb» = 1;
  «string» «uri» = 2;
  repeated «connectrpc».«conformance».«v1».«Header» «headers» = 3;
  repeated «connectrpc».«conformance».«v1».«Header» «raw_query_params» = 4;
  repeated «connectrpc».«conformance».«v1».«RawHTTPRequest».«EncodedQueryParam» «encoded_query_params» = 5;
  «connectrpc».«conformance».«v1».«RawHTTPRequest».«body_Type» «body» = 0;
}

 private  initialize  «protobuf.fileDescriptor.636f6e6e6563747270632f636f6e666f726d616e63652f76312f736572766963652e70726f746f»  :  «Protobuf».«Reflection».«FileDescriptor»  ←  «Protobuf».«Reflection».«generatedPool».«registerFileBase64!»  (  «String».«append»  "Cidjb25uZWN0cnBjL2NvbmZvcm1hbmNlL3YxL3NlcnZpY2UucHJvdG8SGWNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEaJmNvbm5lY3RycGMvY29uZm9ybWFuY2UvdjEvY29uZmlnLnByb3RvGhlnb29nbGUvcHJvdG9idWYvYW55LnByb3RvIp8DChdVbmFyeVJlc3BvbnNlRGVmaW5pdGlvbhJMChByZXNwb25zZV9oZWFkZXJzGAEgAygLMiEuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5IZWFkZXJSD3Jlc3BvbnNlSGVhZGVycxIlCg1yZXNwb25zZV9kYXRhGAIgASgMSABSDHJlc3BvbnNlRGF0YRI4CgVlcnJvchgDIAEoCzIgLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuRXJyb3JIAFIFZXJyb3ISTgoRcmVzcG9uc2VfdHJhaWxlcnMYBCADKAsyIS5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkhlYWRlclIQcmVzcG9uc2VUcmFpbGVycxIqChFyZXNwb25zZV9kZWxheV9tcxgGIAEoDVIPcmVzcG9uc2VEZWxheU1zEk0KDHJhd19yZXNwb25zZRgFIAEoCzIqLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuUmF3SFRUUFJlc3BvbnNlUgtyYXdSZXNwb25zZUIKCghyZXNwb25zZSKQAwoYU3RyZWFtUmVzcG9uc2VEZWZpbml0aW9uEkwKEHJlc3BvbnNlX2hlYWRlcnMYASADKAsyIS5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkhlYWRlclIPcmVzcG9uc2VIZWFkZXJzEiMKDXJlc3BvbnNlX2RhdGEYAiADKAxSDHJlc3BvbnNlRGF0YRIqChFyZXNwb25zZV9kZWxheV9tcxgDIAEoDVIPcmVzcG9uc2VEZWxheU1zEjYKBWVycm9yGAQgASgLMiAuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5FcnJvclIFZXJyb3ISTgoRcmVzcG9uc2VfdHJhaWxlcnMYBSADKAsyIS5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkhlYWRlclIQcmVzcG9uc2VUcmFpbGVycxJNCgxyYXdfcmVzcG9uc2UYBiABKAsyKi5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLlJhd0hUVFBSZXNwb25zZVILcmF3UmVzcG9uc2UilgEKDFVuYXJ5UmVxdWVzdBJjChNyZXNwb25zZV9kZWZpbml0aW9uGAEgASgLMjIuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5VbmFyeVJlc3BvbnNlRGVmaW5pdGlvblIScmVzcG9uc2VEZWZpbml0aW9uEiEKDHJlcXVlc3RfZGF0YRgCIAEoDFILcmVxdWVzdERhdGEiWAoNVW5hcnlSZXNwb25zZRJHCgdwYXlsb2FkGAEgASgLMi0uY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5Db25mb3JtYW5jZVBheWxvYWRSB3BheWxvYWQioAEKFklkZW1wb3RlbnRVbmFyeVJlcXVlc3QSYwoTcmVzcG9uc2VfZGVmaW5pdGlvbhgBIAEoCzIyLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuVW5hcnlSZXNwb25zZURlZmluaXRpb25SEnJlc3BvbnNlRGVmaW5pdGlvbhIhCgxyZXF1ZXN0X2RhdGEYAiABKAxSC3JlcXVlc3REYXRhImIKF0lkZW1wb3RlbnRVbmFyeVJlc3BvbnNlEkcKB3BheWxvYWQYASABKAsyLS5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkNvbmZvcm1hbmNlUGF5bG9hZFIHcGF5bG9hZCKeAQoTU2VydmVyU3RyZWFtUmVxdWVzdBJkChNyZXNwb25zZV9kZWZpbml0aW9uGAEgASgLMjMuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5TdHJlYW1SZXNwb25zZURlZmluaXRpb25SEnJlc3BvbnNlRGVmaW5pdGlvbhIhCgxyZXF1ZXN0X2RhdGEYAiABKAxSC3JlcXVlc3REYXRhIl8KFFNlcnZlclN0cmVhbVJlc3BvbnNlEkcKB3BheWxvYWQYASABKAsyLS5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkNvbmZvcm1hbmNlUGF5bG9hZFIHcGF5bG9hZCKdAQoTQ2xpZW50U3RyZWFtUmVxdWVzdBJjChNyZXNwb25zZV9kZWZpbml0aW9uGAEgASgLMjIuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5VbmFyeVJlc3BvbnNlRGVmaW5pdGlvblIScmVzcG9uc2VEZWZpbml0aW9uEiEKDHJlcXVlc3RfZGF0YRgCIAEoDFILcmVxdWVzdERhdGEiXwoUQ2xpZW50U3RyZWFtUmVzcG9uc2USRwoHcGF5bG9hZBgBIAEoCzItLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuQ29uZm9ybWFuY2VQYXlsb2FkUgdwYXlsb2FkIr0BChFCaWRpU3RyZWFtUmVxdWVzdBJkChNyZXNwb25zZV9kZWZpbml0aW9uGAEgASgLMjMuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5TdHJlYW1SZXNwb25zZURlZmluaXRpb25SEnJlc3BvbnNlRGVmaW5pdGlvbhIfCgtmdWxsX2R1cGxleBgCIAEoCFIKZnVsbER1cGxleBIhCgxyZXF1ZXN0X2RhdGEYAyABKAxSC3JlcXVlc3REYXRhIl0KEkJpZGlTdHJlYW1SZXNwb25zZRJHCgdwYXlsb2FkGAEgASgLMi0uY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5Db25mb3JtYW5jZVBheWxvYWRSB3BheWxvYWQiFgoUVW5pbXBsZW1lbnRlZFJlcXVlc3QiFwoVVW5pbXBsZW1lbnRlZFJlc3BvbnNlIocEChJDb25mb3JtYW5jZVBheWxvYWQSEgoEZGF0YRgBIAEoDFIEZGF0YRJcCgxyZXF1ZXN0X2luZm8YAiABKAsyOS5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkNvbmZvcm1hbmNlUGF5bG9hZC5SZXF1ZXN0SW5mb1ILcmVxdWVzdEluZm8apgIKC1JlcXVlc3RJbmZvEkoKD3JlcXVlc3RfaGVhZGVycxgBIAMoCzIhLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuSGVhZGVyUg5yZXF1ZXN0SGVhZGVycxIiCgp0aW1lb3V0X21zGAIgASgDSABSCXRpbWVvdXRNc4gBARIwCghyZXF1ZXN0cxgDIAMoCzIULmdvb2dsZS5wcm90b2J1Zi5BbnlSCHJlcXVlc3RzEmYKEGNvbm5lY3RfZ2V0X2luZm8YBCABKAsyPC5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkNvbmZvcm1hbmNlUGF5bG9hZC5Db25uZWN0R2V0SW5mb1IOY29ubmVjdEdldEluZm9CDQoLX3RpbWVvdXRfbXMaVgoOQ29ubmVjdEdldEluZm8SRAoMcXVlcnlfcGFyYW1zGAEgAygLMiEuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5IZWFkZXJSC3F1ZXJ5UGFyYW1zIpcBCgVFcnJvchIzCgRjb2RlGAEgASgOMh8uY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5Db2RlUgRjb2RlEh0KB21lc3NhZ2UYAiABKAlIAFIHbWVzc2FnZYgBARIuCgdkZXRhaWxzGAMgAygLMhQuZ29vZ2xlLnByb3RvYnVmLkFueVIHZGV0YWlsc0IKCghfbWVzc2FnZSIyCgZIZWFkZXISEgoEbmFtZRgBIAEoCVIEbmFtZRIUCgV2YWx1ZRgCIAMoCVIFdmFsdWUi0QQKDlJhd0hUVFBSZXF1ZXN0EhIKBHZlcmIYASAB"  "KAlSBHZlcmISEAoDdXJpGAIgASgJUgN1cmkSOwoHaGVhZGVycxgDIAMoCzIhLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuSGVhZGVyUgdoZWFkZXJzEksKEHJhd19xdWVyeV9wYXJhbXMYBCADKAsyIS5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkhlYWRlclIOcmF3UXVlcnlQYXJhbXMSbQoUZW5jb2RlZF9xdWVyeV9wYXJhbXMYBSADKAsyOy5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLlJhd0hUVFBSZXF1ZXN0LkVuY29kZWRRdWVyeVBhcmFtUhJlbmNvZGVkUXVlcnlQYXJhbXMSQgoFdW5hcnkYBiABKAsyKi5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLk1lc3NhZ2VDb250ZW50c0gAUgV1bmFyeRJDCgZzdHJlYW0YByABKAsyKS5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLlN0cmVhbUNvbnRlbnRzSABSBnN0cmVhbRqOAQoRRW5jb2RlZFF1ZXJ5UGFyYW0SEgoEbmFtZRgBIAEoCVIEbmFtZRJACgV2YWx1ZRgCIAEoCzIqLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuTWVzc2FnZUNvbnRlbnRzUgV2YWx1ZRIjCg1iYXNlNjRfZW5jb2RlGAMgASgIUgxiYXNlNjRFbmNvZGVCBgoEYm9keSLSAQoPTWVzc2FnZUNvbnRlbnRzEhgKBmJpbmFyeRgBIAEoDEgAUgZiaW5hcnkSFAoEdGV4dBgCIAEoCUgAUgR0ZXh0Ej0KDmJpbmFyeV9tZXNzYWdlGAMgASgLMhQuZ29vZ2xlLnByb3RvYnVmLkFueUgAUg1iaW5hcnlNZXNzYWdlEkgKC2NvbXByZXNzaW9uGAQgASgOMiYuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5Db21wcmVzc2lvblILY29tcHJlc3Npb25CBgoEZGF0YSLvAQoOU3RyZWFtQ29udGVudHMSSgoFaXRlbXMYASADKAsyNC5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLlN0cmVhbUNvbnRlbnRzLlN0cmVhbUl0ZW1SBWl0ZW1zGpABCgpTdHJlYW1JdGVtEhQKBWZsYWdzGAEgASgNUgVmbGFncxIbCgZsZW5ndGgYAiABKA1IAFIGbGVuZ3RoiAEBEkQKB3BheWxvYWQYAyABKAsyKi5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLk1lc3NhZ2VDb250ZW50c1IHcGF5bG9hZEIJCgdfbGVuZ3RoIr8CCg9SYXdIVFRQUmVzcG9uc2USHwoLc3RhdHVzX2NvZGUYASABKA1SCnN0YXR1c0NvZGUSOwoHaGVhZGVycxgCIAMoCzIhLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuSGVhZGVyUgdoZWFkZXJzEkIKBXVuYXJ5GAMgASgLMiouY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5NZXNzYWdlQ29udGVudHNIAFIFdW5hcnkSQwoGc3RyZWFtGAQgASgLMikuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5TdHJlYW1Db250ZW50c0gAUgZzdHJlYW0SPQoIdHJhaWxlcnMYBSADKAsyIS5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLkhlYWRlclIIdHJhaWxlcnNCBgoEYm9keTK4BQoSQ29uZm9ybWFuY2VTZXJ2aWNlEloKBVVuYXJ5EicuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5VbmFyeVJlcXVlc3QaKC5jb25uZWN0cnBjLmNvbmZvcm1hbmNlLnYxLlVuYXJ5UmVzcG9uc2UScQoMU2VydmVyU3RyZWFtEi4uY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5TZXJ2ZXJTdHJlYW1SZXF1ZXN0Gi8uY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5TZXJ2ZXJTdHJlYW1SZXNwb25zZTABEnEKDENsaWVudFN0cmVhbRIuLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuQ2xpZW50U3RyZWFtUmVxdWVzdBovLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuQ2xpZW50U3RyZWFtUmVzcG9uc2UoARJtCgpCaWRpU3RyZWFtEiwuY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5CaWRpU3RyZWFtUmVxdWVzdBotLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuQmlkaVN0cmVhbVJlc3BvbnNlKAEwARJyCg1VbmltcGxlbWVudGVkEi8uY29ubmVjdHJwYy5jb25mb3JtYW5jZS52MS5VbmltcGxlbWVudGVkUmVxdWVzdBowLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuVW5pbXBsZW1lbnRlZFJlc3BvbnNlEn0KD0lkZW1wb3RlbnRVbmFyeRIxLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuSWRlbXBvdGVudFVuYXJ5UmVxdWVzdBoyLmNvbm5lY3RycGMuY29uZm9ybWFuY2UudjEuSWRlbXBvdGVudFVuYXJ5UmVzcG9uc2UiA5ACAWIGcHJvdG8z"  ) 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«UnaryResponseDefinition»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.UnaryResponseDefinition"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«UnaryResponseDefinition».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«UnaryResponseDefinition».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«StreamResponseDefinition»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.StreamResponseDefinition"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«StreamResponseDefinition».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«StreamResponseDefinition».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«UnaryRequest»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.UnaryRequest"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«UnaryRequest».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«UnaryRequest».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«UnaryResponse»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.UnaryResponse"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«UnaryResponse».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«UnaryResponse».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«IdempotentUnaryRequest»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.IdempotentUnaryRequest"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«IdempotentUnaryRequest».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«IdempotentUnaryRequest».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«IdempotentUnaryResponse»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.IdempotentUnaryResponse"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«IdempotentUnaryResponse».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«IdempotentUnaryResponse».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ServerStreamRequest»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ServerStreamRequest"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ServerStreamRequest».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ServerStreamRequest».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ServerStreamResponse»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ServerStreamResponse"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ServerStreamResponse».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ServerStreamResponse».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ClientStreamRequest»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ClientStreamRequest"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ClientStreamRequest».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ClientStreamRequest».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ClientStreamResponse»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ClientStreamResponse"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ClientStreamResponse».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ClientStreamResponse».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«BidiStreamRequest»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.BidiStreamRequest"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«BidiStreamRequest».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«BidiStreamRequest».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«BidiStreamResponse»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.BidiStreamResponse"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«BidiStreamResponse».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«BidiStreamResponse».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«UnimplementedRequest»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.UnimplementedRequest"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«UnimplementedRequest».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«UnimplementedRequest».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«UnimplementedResponse»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.UnimplementedResponse"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«UnimplementedResponse».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«UnimplementedResponse».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ConformancePayload»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ConformancePayload"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ConformancePayload».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ConformancePayload».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ConformancePayload».«RequestInfo»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ConformancePayload.RequestInfo"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ConformancePayload».«RequestInfo».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ConformancePayload».«RequestInfo».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«ConformancePayload».«ConnectGetInfo»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.ConformancePayload.ConnectGetInfo"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«ConformancePayload».«ConnectGetInfo».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«ConformancePayload».«ConnectGetInfo».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«Error»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.Error"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«Error».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«Error».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«Header»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.Header"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«Header».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«Header».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«RawHTTPRequest»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.RawHTTPRequest"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«RawHTTPRequest».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«RawHTTPRequest».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«RawHTTPRequest».«EncodedQueryParam»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.RawHTTPRequest.EncodedQueryParam"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«RawHTTPRequest».«EncodedQueryParam».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«RawHTTPRequest».«EncodedQueryParam».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«MessageContents»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.MessageContents"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«MessageContents».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«MessageContents».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«StreamContents»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.StreamContents"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«StreamContents».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«StreamContents».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«StreamContents».«StreamItem»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.StreamContents.StreamItem"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«StreamContents».«StreamItem».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«StreamContents».«StreamItem».«protobuf.internal».«fromMessage»  «wire»  } 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «connectrpc».«conformance».«v1».«RawHTTPResponse»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "connectrpc.conformance.v1.RawHTTPResponse"  ,  «toMessagePartial»  :=  «connectrpc».«conformance».«v1».«RawHTTPResponse».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «connectrpc».«conformance».«v1».«RawHTTPResponse».«protobuf.internal».«fromMessage»  «wire»  } 

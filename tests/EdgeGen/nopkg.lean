module

public import Protobuf.Encoding
public import Protobuf.ProtoMessage
public import Protobuf.Base64
public import Protobuf.Reflection
meta import Protobuf.Notation


public section

open Protobuf Encoding
open scoped Protobuf.Notation
message «Hello» {
  «string» «name» = 1;
}

 private  initialize  «protobuf.fileDescriptor.6e6f706b672e70726f746f»  :  «Protobuf».«Reflection».«FileDescriptor»  ←  «Protobuf».«Reflection».«generatedPool».«registerFileBase64!»  "Cgtub3BrZy5wcm90byIbCgVIZWxsbxISCgRuYW1lGAEgASgJUgRuYW1lMiIKB0dyZWV0ZXISFwoFR3JlZXQSBi5IZWxsbxoGLkhlbGxvYgZwcm90bzM=" 

 instance  :  «Protobuf».«Reflection».«ReflectMessage»  «Hello»  :=  {  «descriptor»  :=  «Protobuf».«Reflection».«MessageDescriptor».«mk»  «Protobuf».«Reflection».«generatedPool»  "Hello"  ,  «toMessagePartial»  :=  «Hello».«protobuf.internal».«toMessagePartial»  ,  «fromMessage»  :=  fun  «wire»  =>  «Hello».«protobuf.internal».«fromMessage»  «wire»  } 

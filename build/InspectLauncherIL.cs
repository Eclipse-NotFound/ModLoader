using System;
using System.IO;
using System.Text;
using System.Reflection;
using System.Reflection.Emit;
using System.Collections.Generic;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
public static class InspectLauncherIL {
 static string Name(MetadataReader r, EntityHandle h) {
  switch(h.Kind) {
   case HandleKind.TypeDefinition: var t=r.GetTypeDefinition((TypeDefinitionHandle)h); return r.GetString(t.Namespace)+"."+r.GetString(t.Name);
   case HandleKind.TypeReference: var tr=r.GetTypeReference((TypeReferenceHandle)h); return r.GetString(tr.Namespace)+"."+r.GetString(tr.Name);
   case HandleKind.MethodDefinition: var m=r.GetMethodDefinition((MethodDefinitionHandle)h);return Name(r,m.GetDeclaringType())+"::"+r.GetString(m.Name);
   case HandleKind.MemberReference: var mr=r.GetMemberReference((MemberReferenceHandle)h);return Name(r,mr.Parent)+"::"+r.GetString(mr.Name);
   case HandleKind.MethodSpecification:return Name(r,r.GetMethodSpecification((MethodSpecificationHandle)h).Method);
   case HandleKind.FieldDefinition:return r.GetString(r.GetFieldDefinition((FieldDefinitionHandle)h).Name);
   default:return h.Kind+":"+MetadataTokens.GetToken(h).ToString("X8");
  }
 }
 public static string Read(string path,string filter) {
  var codes=new Dictionary<short,OpCode>();foreach(var f in typeof(OpCodes).GetFields(BindingFlags.Public|BindingFlags.Static)) if(f.FieldType==typeof(OpCode)) {var c=(OpCode)f.GetValue(null);codes[c.Value]=c;}
  var output=new StringBuilder();using(var stream=File.OpenRead(path))using(var pe=new PEReader(stream)) {
   var r=pe.GetMetadataReader();foreach(var mh in r.MethodDefinitions) {
    var m=r.GetMethodDefinition(mh);if(m.RelativeVirtualAddress==0)continue;
    var b=pe.GetMethodBody(m.RelativeVirtualAddress);byte[] il=b.GetILBytes();int i=0;var lines=new StringBuilder();
    while(i<il.Length){int off=i;short n=il[i++];if(n==254)n=(short)(0xfe00|il[i++]);var op=codes[n];string arg="";int size=0;
     switch(op.OperandType){
      case OperandType.InlineNone:break;
      case OperandType.ShortInlineBrTarget:case OperandType.ShortInlineI:case OperandType.ShortInlineVar:size=1;break;
      case OperandType.InlineVar:size=2;break;
      case OperandType.InlineI8:case OperandType.InlineR:size=8;break;
      case OperandType.InlineSwitch:int count=BitConverter.ToInt32(il,i);size=4+4*count;break;
      default:size=4;break;
     }
     if(size==4){int token=BitConverter.ToInt32(il,i);
      if(op.OperandType==OperandType.InlineString)arg="\""+r.GetUserString(MetadataTokens.UserStringHandle(token&0xffffff)).Replace("\n","\\n")+"\"";
      else if(op.OperandType==OperandType.InlineMethod||op.OperandType==OperandType.InlineField||op.OperandType==OperandType.InlineType||op.OperandType==OperandType.InlineTok)arg=Name(r,MetadataTokens.EntityHandle(token));
      else arg=token.ToString();
     } else if(size>0)arg=BitConverter.ToString(il,i,size);
     i+=size;lines.AppendLine(off.ToString("X4")+" "+op.Name+" "+arg);
    }
    string name=Name(r,mh);if(name.IndexOf(filter,StringComparison.OrdinalIgnoreCase)>=0||lines.ToString().IndexOf(filter,StringComparison.OrdinalIgnoreCase)>=0) {
     output.AppendLine("METHOD "+name+" RVA "+m.RelativeVirtualAddress.ToString("X"));output.Append(lines);
     foreach(var e in b.ExceptionRegions) output.AppendLine("EH "+e.Kind+" try="+e.TryOffset+"+"+e.TryLength+" handler="+e.HandlerOffset+"+"+e.HandlerLength);
    }
   }
  }return output.ToString();
 }
}

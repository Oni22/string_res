import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:string_res/src/fson_base.dart';
import 'package:string_res/src/fson_models.dart';
import 'package:string_res/src/fson_schema.dart';
import 'package:string_res/src/fson_validator.dart';

class FSON {

  List<FSONNode> parse(String frData) {

    List<FSONNode> fsonModels = [];

    var idBlocks = frData.split(RegExp(r"\},"));
    idBlocks.removeWhere((s) => s.length == 0);

    idBlocks.forEach((block) {
      var blockNameLangs = block.split(RegExp(r"\{"));
      var fsonModel = FSONNode(
        name: blockNameLangs[0].trim(),
      );

      var langs = blockNameLangs[1];

      var fsonValidatorId = FSONValidator.validateStringId(fsonModel.name);
      if(!fsonValidatorId.isValid) {
        throw FormatException(fsonValidatorId.message + " " + "at id: ${fsonModel.name}");
      }

      langs.replaceAll("}","").trim().split(RegExp(r"(,)(?![^[]*\])")).forEach((lang) {
        var langCodeText = lang.split(":");
        var langCode = langCodeText[0].trim();
        var text = langCodeText[1].trim();

        var keyValidator = FSONValidator.validateKey(langCode);
        if(!keyValidator.isValid) {
          throw FormatException(fsonValidatorId.message + " " + "at id: ${fsonModel.name}");
        }

        var keyValueNode = FSONKeyValueNode(
          key: langCode,
        );

        var fsonValidatorText = FSONValidator.validateText(text);
        if(!fsonValidatorText.isValid) {
          throw FormatException(fsonValidatorText.message + " " + "at id: ${fsonModel.name}");
        }

        if(text.contains(RegExp(r"\[(.*?)\]"))) {
          var plurals = text.replaceAll("[", "").replaceAll("]", "").trim().split(",");
          keyValueNode.arrayList = plurals;
        } else {
          keyValueNode.value = text;
        }

        fsonModel.keyValueNodes.add(keyValueNode);
      });
      fsonModels.add(fsonModel);
    });
    return fsonModels;
  }

  void buildResource(FSONSchema schema,String readFilesFrom, String saveOutputAs, String parentClassName,FSONBase child) async{

    if(child is FSONBase == false) {
      throw Exception("Membertype doens't extend from FSONBase class!");
    }

    var relativePath = path.relative(readFilesFrom);
    var parseContent = await combineResources(relativePath);
    List<String> currentIds =  [];

    String finalContent = "import 'package:string_res/string_res.dart';\nclass $parentClassName {\n";
    var fsons = FSON().parse(parseContent);
    for(var fson in fsons) {
      
      if(currentIds.contains(fson.name)) {
        throw FormatException("Id already exists! at id: ${fson.name}");
      } else {
        currentIds.add(fson.name);
      }

      if((schema?.requiredKeys?.length ?? 0) < 1 && (schema?.keys?.length ?? 0) < 1) {
        throw FormatException("Required keys and optional keys shouldn't be null or empty at the same time. Use at least one of these to specify keys for your schema");
      }

      if((fson.keyValueNodes?.length ?? 0) < 1) throw FormatException("Please add keys to FSONNode! At ${fson.name}"); 

      schema.requiredKeys?.forEach((k) {
          if(fson.keyValueNodes.any((f) => f.key == k) == false)
            throw FormatException("Key $k is required! At ${fson.name}!");
      });
  
      fson.keyValueNodes.forEach((kv) {
          if(schema.keys?.contains(kv.key) == false)
            throw FormatException("Key ${kv.key} not supported! At ${fson.name}!");
      });

      if(schema.fsonCustomValidate != null) {
        schema.fsonCustomValidate(fson);
      }

      Map<String,dynamic> map = {};

      for(var kv in fson.keyValueNodes) {
        if(isReference(kv)) {
          var value = await fetchReference(kv);
          map["\"${kv.key}\""] = value ?? "";
        } else {
          if(kv.arrayList.length > 0) {
          map["\"${kv.key}\""] = kv.arrayList;
          } 
          else {
            map["\"${kv.key}\""] = kv.value;
          }
        }                 
      }
      finalContent += "\tstatic ${child.runtimeType} ${fson.name} = ${child.runtimeType}(map: ${map.toString()} ,name: \"${fson.name}\");\n";
    }

    finalContent += "}";
    File(relativePath + "/$saveOutputAs").writeAsString(finalContent);

  }

  Future<FSONKeyValueNode> loadKeyValueNode(String resourceId, String id, String key) async {
    var relativePath = path.relative("lib/$resourceId/");
    var parsedContent = await combineResources(relativePath);
    var node = parse(parsedContent).firstWhere((f) => f.name == id);
    return node.keyValueNodes.firstWhere((kv) => kv.key == key);
  }

  Future<String> combineResources(String directoryPath) async {
    var dir = Directory(directoryPath);

    if(!dir.existsSync()) { 
      dir.createSync();
    }

    var parseContent = "";
    var files = dir.listSync();

    for(var fileEntity in files) {
      if(path.extension(fileEntity.path) == ".fson") {
        var file = File(fileEntity.path);
        var content = await file.readAsString();
        parseContent += content.replaceAll("\n", "").trim() + ",";
      }
    }
    return parseContent;
  }

  bool isReference(FSONKeyValueNode kv) {
    if(kv?.value?.startsWith("\"#(") == true && kv?.value?.endsWith(")\"") == true) 
      return true;
    return false;
  }

  bool isExternalReference(FSONKeyValueNode kv) {
    if(isReference(kv)) {
      var splitted = kv.value.replaceAll("\"#(", "").replaceAll(")\"", "").split(".");
      if((splitted[0].contains("colors") || splitted[0].contains("styles") || splitted[0].contains("strings")) && splitted.length == 3) {
        return true;
      } else {
        return false;
      }
    }
    return false;
  }

  Future<String> fetchReference(FSONKeyValueNode kv) async {

    FSONKeyValueNode currentKV = kv;

    if(isReference(kv)) {
      var splitted = currentKV.value.replaceAll("\"#(", "").replaceAll(")\"", "").split(".");
      var namespace = "";
      var id = "";
      var key = "";
      
      if(isExternalReference(kv)) {
        namespace = splitted[0];
        id = splitted[1];
        key = splitted[2];
        var keyValue = await loadKeyValueNode(namespace, id, key);
        var fetched = await fetchReference(keyValue);
        return fetched;
      } 
    }
    return kv.value ?? "";
  }
}
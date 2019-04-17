{.experimental: "codeReordering".}
import options
import xmltree
import xmltools  # TODO: remove this dependency as it's too big & noisy
import fp / map  # TODO: also remove this

# References:
# - https://github.com/aosp-mirror/platform_frameworks_base/blob/e5cf74326dc37e87c24016640b535a269499e1ec/tools/aapt/XMLNode.cpp#L1089
# - https://android.googlesource.com/platform/frameworks/base/+/dc36bb6dea837608c29c177a7ea8cf46b6a0cd53/tools/aapt/XMLNode.cpp
# - https://github.com/sdklite/aapt/blob/9e6d1ad98469dffbc9940821551bd7a2e07dd1e0/src/main/java/com/sdklite/aapt/AssetEditor.java

type
  DataType = enum
    dtString = 0x03,
    dtInt = 0x10
  KnownAttr = object
    name: string
    xmlns: string       # namespace
    rawDefault: string  # "" means none
    typ: DataType
    intDefault: Option[uint32]  # only relevant if typ==dtInt

const
  nsAndroid = "http://schemas.android.com/apk/res/android"
  knownManifestAttrs = @[
    KnownAttr(name: "compileSdkVersion", xmlns: nsAndroid, typ: dtInt, intDefault: some(28'u32)),
    KnownAttr(name: "compileSdkVersionCodename", xmlns: nsAndroid, rawDefault: "9", typ: dtString),
    KnownAttr(name: "platformBuildVersionCode", rawDefault: "28", typ: dtInt, intDefault: some(28'u32)),
    KnownAttr(name: "platformBuildVersionName", rawDefault: "9", typ: dtInt, intDefault: some(9'u32)),
  ]
  knownResources = @[
    ("compileSdkVersion", 0x01010572),
    ("compileSdkVersionCodename", 0x01010573),
    ("label", 0x01010001),
    ("name", 0x01010003),
  ]


proc marcoCompile*(inputXml: string): string =
  let
    xml = Node.fromStringE(inputXml)
    namespaces = xml.namespaces
  for attr in knownManifestAttrs:
    let
      ns = namespaces.get(attr.xmlns)
      qname = ns.get("") $: attr.name
    if xml.attr(qname).isNone:
      xml.XmlNode.attrs[qname] = attr.rawDefault
  echo xml



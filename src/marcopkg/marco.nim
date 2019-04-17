{.experimental: "codeReordering".}
import options
import xmltree
import xmlparser
import strtabs

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
    rawDefault: string  # "" means none
    stripRaw: bool
    typ: DataType
  ManifestError* = object of CatchableError

const
  nsAndroid = "http://schemas.android.com/apk/res/android"
  knownManifestAttrs = @[
    KnownAttr(name: "android:compileSdkVersion", rawDefault: "28", typ: dtInt, stripRaw: true),
    KnownAttr(name: "android:compileSdkVersionCodename", rawDefault: "9", typ: dtString),
    KnownAttr(name: "platformBuildVersionCode", rawDefault: "28", typ: dtInt),
    KnownAttr(name: "platformBuildVersionName", rawDefault: "9", typ: dtInt),
  ]
  knownResources = @[
    ("compileSdkVersion", 0x01010572),
    ("compileSdkVersionCodename", 0x01010573),
    ("label", 0x01010001),
    ("name", 0x01010003),
  ]


proc marcoCompile*(inputXml: string): string =
  let
    xml = parseXml(inputXml)
  if xml.tag != "manifest":
    raise newException(ManifestError, "root node must be <manifest>")
  if not xml.attrs.hasKey("xmlns:android"):
    raise newException(ManifestError, "the <manifest> node must have 'xmlns:android' attribute")
  if xml.attrs["xmlns:android"] != nsAndroid:
    raise newException(ManifestError, "the <manifest> node's attribute 'xmlns:android' must have value \"" & nsAndroid & "\"")
  for attr in knownManifestAttrs:
    if attr.name notin xml.attrs:
      xml.attrs[attr.name] = attr.rawDefault
  echo xml


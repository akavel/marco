{.experimental: "codeReordering".}
import options
import xmltree
import xmlparser
import strtabs
import sortedset
import tables

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
  StringSets = object
    res: SortedSet[string]
    other: SortedSet[string]
  ManifestError* = object of CatchableError

const
  nsAndroid = "http://schemas.android.com/apk/res/android"
  knownManifestAttrs = @[
    KnownAttr(name: "android:compileSdkVersion", rawDefault: "28", typ: dtInt, stripRaw: true),
    KnownAttr(name: "android:compileSdkVersionCodename", rawDefault: "9", typ: dtString),
    KnownAttr(name: "platformBuildVersionCode", rawDefault: "28", typ: dtInt),
    KnownAttr(name: "platformBuildVersionName", rawDefault: "9", typ: dtInt),
  ]
  knownResources = [
    ("compileSdkVersion", 0x01010572),
    ("compileSdkVersionCodename", 0x01010573),
    ("label", 0x01010001),
    ("name", 0x01010003),
  ].toTable


proc marcoCompile*(inputXml: string): string =
  # Parse + verify namespaces in a dumb, hacky way
  let
    xml = parseXml(inputXml)
  if xml.tag != "manifest":
    raise newException(ManifestError, "root node must be <manifest>")
  if not xml.attrs.hasKey("xmlns:android"):
    raise newException(ManifestError, "the <manifest> node must have 'xmlns:android' attribute")
  if xml.attrs["xmlns:android"] != nsAndroid:
    raise newException(ManifestError, "the <manifest> node's attribute 'xmlns:android' must have value \"" & nsAndroid & "\"")

  # Set default attributes if necessary
  for attr in knownManifestAttrs:
    if attr.name notin xml.attrs:
      xml.attrs[attr.name] = attr.rawDefault

  # Collect all strings
  var strings = StringSets()
  init(strings.res)
  init(strings.other)
  collectStrings(xml, strings)
  echo strings.res.seq[:string]
  echo strings.other.seq[:string]

proc collectStrings(xml: XmlNode, strings: var StringSets) =
  if xml.kind != xnElement:
    return
  let (ns, tag) = xml.tag.splitQName
  strings.incl(tag)
  if xml.attrsLen > 0:
    for k, v in xml.attrs:
      if k == "xmlns":
        continue
      let (ns, attr) = k.splitQName
      if ns == "xmlns":
        continue
      strings.incl(attr)
      strings.incl(v)
  for child in xml:
    collectStrings(child, strings)

proc splitQName(qname: string): (string, string) =
  let split = qname.split(":")
  if split.len > 1:
    return (split[0], split[1])
  else:
    return ("", split[0])

proc incl(strings: var StringSets, item: string) =
  if item in knownResources:
    strings.res.incl(item)
  else:
    strings.other.incl(item)


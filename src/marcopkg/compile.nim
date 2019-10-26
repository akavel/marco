{.experimental: "codeReordering".}
import options
import xmltree
import xmlparser
import strtabs
import strutils
import sets
import tables
import critbits

import blob
import consts

# References:
# - https://github.com/aosp-mirror/platform_frameworks_base/blob/e5cf74326dc37e87c24016640b535a269499e1ec/tools/aapt/XMLNode.cpp#L1089
# - https://android.googlesource.com/platform/frameworks/base/+/dc36bb6dea837608c29c177a7ea8cf46b6a0cd53/tools/aapt/XMLNode.cpp
# - https://github.com/sdklite/aapt/blob/9e6d1ad98469dffbc9940821551bd7a2e07dd1e0/src/main/java/com/sdklite/aapt/AssetEditor.java

type
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
  knownResources = [
    ("compileSdkVersion", 0x01010572'u32),
    ("compileSdkVersionCodename", 0x01010573'u32),
    ("label", 0x01010001'u32),
    ("name", 0x01010003'u32),
  ].toTable



proc marcoCompile*(inputXml: string): string =
  return marcoCompile(parseXml(inputXml))

proc marcoCompile*(xml: XmlNode): string =
  # Parse + verify namespaces in a dumb, hacky way
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
  let (resources, nonResources) = collectStrings(xml)
  var strings = newSeq[string]()
  var stringsMap: CritBitTree[uint32]
  for i, s in resources:
    strings.add(s)
    stringsMap[s] = i.uint32
  for i, s in nonResources:
    strings.add(s)
    stringsMap[s] = uint32(resources.len + i)
  # echo buckets.res #.seq[:string]
  # echo buckets.other #.seq[:string]

  # Partially render header
  var res: Blob
  res.put16 ctXML.ord
  res.put16 8   # header size
  res.put32 >>: fileSizeSlot

  # Render list of strings
  let stringsPos = res.pos
  res.put16 ctStringPool.ord
  res.put16 0x1c   # header size
  res.put32 >>: stringsSizeSlot
  res.put32 uint32(strings.len)
  res.put32 0   # style count
  res.put32 0   # flags TODO(akavel): try writing utf-8, not utf-16
  res.put32 >>: stringsStartSlot
  res.put32 0   # styles start
  var stringOffsetSlots = newSeq[Slot32]()
  for i in 0 ..< strings.len:
    res.put32 >>: slot
    stringOffsetSlots.add slot
  let stringsStartPos = res.pos
  res[stringsStartSlot] = stringsStartPos - stringsPos
  for i, s in strings:
    res[stringOffsetSlots[i]] = res.pos - stringsStartPos
    res.put16 s.len.uint16   # TODO: handle longer strings
    for c in s:
      res.put16 c.ord.uint16
    res.put16 0
  res.pad32() # Note: when chunk size was not rounded to 4 bytes, I got a validation error
  res[stringsSizeSlot] = res.pos - stringsPos

  # Render "XML resource map"
  let resMapPos = res.pos
  res.put16 ctXMLResourceMap.ord
  res.put16 8   # header size
  res.put32 >>: resMapSizeSlot
  for s in resources:
    res.put32 knownResources[s]
  res[resMapSizeSlot] = res.pos - resMapPos

  # Render XML tree
  var lineNo = 2'u32
  renderXML(res, xml, stringsMap, lineNo)

  res[fileSizeSlot] = res.pos
  result = res.string

proc collectStrings(xml: XmlNode): (OrderedSet[string], OrderedSet[string]) =
  if xml.kind != xnElement:
    return
  var
    resources = initOrderedSet[string]()
    other = initOrderedSet[string]()
  # Helper funcs
  proc incl(s: string) =
    if s in knownResources:
      resources.incl(s)
    else:
      other.incl(s)
  proc recurse(xml: XmlNode) =
    incl(xml.tag.splitQName().name)
    if xml.attrsLen > 0:
      for k, v in xml.attrs:
        # TODO: handle namespaces & namespace definitions
        # (xmlns) properly
        incl(k.splitQName().name)
        incl(v)
    for child in xml:
      recurse(child)
  # Proper body of the proc
  recurse(xml)
  return (resources, other)

proc splitQName(qname: string): tuple[ns: string, name: string] =
  ## Split XML "qualified name" (namespace:name) to the
  ## namespace and name components. For simple,
  ## non-qualified names, empty namespace string is
  ## returned.
  let split = qname.split(":")
  if split.len > 1:
    return (split[0], split[1])
  else:
    return ("", split[0])

proc renderXML(res: var Blob, xml: XmlNode, stringsMap: CritBitTree[uint32], lineNo: var uint32) =
  if xml.kind != xnElement:
    return

  # Open new XML namespace, if needed
  var newNS = false
  if xml.attrsLen > 0 and "xmlns:android" in xml.attrs:
    # TODO: generalize to fully properly handle namespaces
    # (current code only handles xmlns:android)
    newNS = true
    let (pos, sizeSlot) = res.putXML(ctXMLStartNS, lineNo)
    dec(lineNo)
    res.put32 stringsMap["android"]
    res.put32 stringsMap[xml.attrs["xmlns:android"]]
    res[sizeSlot] = res.pos - pos

  # Render XML element start
  let (pos, sizeSlot) = res.putXML(ctXMLStartElement, lineNo)
  let (ns, tag) = xml.tag.splitQName
  res.put32 0xffff_ffff'u32   # TODO: handle namespaces
  res.put32 stringsMap[tag]
  res.put16 0x14'u16   # attr start
  res.put16 0x14'u16   # attr size
  var attrs = xml.attrs.stripNamespaces()
  res.put16 attrs.len.uint16
  res.put16 0   # ID index
  res.put16 0   # class index
  res.put16 0   # style index

  # Render attributes
  for k, v in attrs:
    # echo k, "=", v
    let (ns, attr) = k.splitQName
    if ns == "android":
      res.put32 stringsMap[nsAndroid]
    else:
      res.put32 0xffff_ffff'u32   # TODO: handle other namespaces too
    res.put32 stringsMap[attr]
    var
      typ = dtString
      raw = stringsMap[v]
      stripRaw = false
      data = raw
      isKnown = isKnownManifestAttr(k)
    if tag == "manifest" and isKnown.isSome:
      typ = isKnown.get.typ
      if isKnown.get.stripRaw:
        raw = 0xffff_ffff'u32
    res.put32 raw
    res.put16 8       # size
    res.putc chr(0)   # res0
    res.putc chr(typ.ord)
    if typ == dtInt:
      data = v.parseInt.uint32
    res.put32 data
  res[sizeSlot] = res.pos - pos

  # Render child elements
  for child in xml:
    renderXML(res, child, stringsMap, lineNo)

  # Render XML element end
  let (posEnd, sizeSlotEnd) = res.putXML(ctXMLEndElement, lineNo)
  res.put32 0xffff_ffff'u32   # TODO: handle namespaces
  res.put32 stringsMap[tag]
  res[sizeSlotEnd] = res.pos - posEnd

  # Close an XML namespace, if needed
  if newNS:
    dec(lineNo)
    let (pos, sizeSlot) = res.putXML(ctXMLEndNS, lineNo)
    res.put32 stringsMap["android"]
    res.put32 stringsMap[xml.attrs["xmlns:android"]]
    res[sizeSlot] = res.pos - pos

proc putXML(res: var Blob, typ: ChunkType, lineNo: var uint32): tuple[pos: uint32, sizeSlot: Slot32] =
  result.pos = res.pos
  res.put16 typ.ord.uint16
  res.put16 0x10'u16
  res.put32 >> result.sizeSlot
  res.put32 lineNo
  inc(lineNo)
  res.put32 0xffff_ffff'u32   # comment index

proc stripNamespaces(attrs: XmlAttributes): CritBitTree[string] =
  if attrs == nil:
    return
  for k, v in attrs:
    if k != "xmlns" and not k.startsWith("xmlns:"):
      result[k] = v

proc isKnownManifestAttr(name: string): Option[KnownAttr] =
  for attr in knownManifestAttrs:
    if attr.name == name:
      return some(attr)


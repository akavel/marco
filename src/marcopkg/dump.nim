# This file contains a simple parser for binary
# AndroidManifest.xml files. The output format is intended
# to be similar to what `aapt dump` would print.

{.experimental: "codeReordering".}
import streams
import strutils

import consts

type
  MarcoStream = distinct Stream
  ProtocolError* = object of CatchableError
  ExpectationError* = object of CatchableError

proc marcoDump*(inputBin: string): string {.inline.} =
  return marcoDump(newStringStream(inputBin))

proc marcoDump*(inputBin: Stream): string =
  var s = inputBin.MarcoStream

  # File header
  s.expect(ctXML.ord.uint16)
  result.add("Binary XML\n")
  s.expect(8'u16)  # header size
  discard s.read_u32()  # FIXME: verify chunk size

  # Read "strings pool"
  # Chunk header
  s.expect(ctStringPool.ord.uint16)
  s.expect(0x1c'u16)  # header size
  discard s.read_u32()  # FIXME: verify chunk size
  let nStrings = s.read_u32().int
  s.expect(0'u32)  # style counter
  s.expect(0'u32)  # flags
  discard s.read_u32()  # FIXME: verify strings start
  s.expect(0'u32)  # styles start
  # Strings offsets
  for i in 0 ..< nStrings:
    discard s.read_u32()  # FIXME: verify strings offsets
  # Read strings
  var pool = newSeq[string](nStrings)
  for i in 0 ..< nStrings:
    let length = s.read_u16()  # FIXME: support long strings
    var buf = newString(length)
    for j in 0 ..< length.int:
      let ch = s.read_u16()
      # FIXME: support full UTF-16
      if ch > 255'u16: raise newException(ExpectationError, "non-ASCII characters not yet implemented")
      buf[j] = ch.uint8.chr
    s.expect(0'u16)
    pool[i] = buf

  # Read "XML resources map"
  # Chunk header
  s.expect(ctXMLResourceMap.ord.uint16)
  s.expect(8'u16)  # header size
  let mapSize = s.read_u32().int
  var resIDs = newSeq[uint32](Natural((mapSize - 8) / 4))
  for i in 0 ..< resIDs.len:
    resIDs[i] = s.read_u32()

  # Read "XML nodes"
  var
    indent = ""
    stack = newSeq[string]()
    prevLineNo = 1'u32
  while not s.Stream.atEnd:
    let
      chunkType = s.read_u16()
      headerSize = s.read_u16()  # FIXME: verify
      chunkSize = s.read_u32()  # FIXME: verify
      lineNo = s.read_u32()
    s.expect(0xffff_ffff'u32)  # comment index
    if lineNo < prevLineNo:    # verify lineNo
      raise newException(ExpectationError, "expected increasing lineNo, got " & $lineNo & " < " & $prevLineNo)
    case chunkType.ChunkType
    of ctXMLStartNS:
      let
        nsPrefix = s.read_u32().int
        nsURI = s.read_u32().int
      result.add(indent & "N: " & pool[nsPrefix] & "=" & pool[nsURI] & "\n")
      indent.add("  ")
      stack.add("N " & nsPrefix.toHex & " " & nsURI.toHex)
    of ctXMLEndNS:
      let
        nsPrefix = s.read_u32().int
        nsURI = s.read_u32().int
        top = stack.pop()
        wanted = "N " & nsPrefix.toHex & " " & nsURI.toHex
      doAssert(top == wanted, $top & " != " & $wanted)
      indent.setLen(indent.len-2)
    of ctXMLStartElement:
      let
        ns = s.read_u32()
        name = s.read_u32().int
      s.expect(0x14'u16)  # attr start
      s.expect(0x14'u16)  # attr size
      let
        nAttr = s.read_u16().int
      s.expect(0'u16)  # ID index
      s.expect(0'u16)  # class index
      s.expect(0'u16)  # style index
      result.add(indent & "E: ")
      if ns != 0xffff_ffff'u32:
        result.add(pool[ns.int] & ":")
      result.add(pool[name] & "\n")
      indent.add("  ")
      stack.add("E " & ns.toHex & " " & name.toHex)
      # Attributes
      for i in 0 ..< nAttr:
        let
          ns = s.read_u32()
          name = s.read_u32().int
          raw = s.read_u32()
        s.expect(8'u16)  # size
        s.expect(0'u8)   # res0
        let
          dataType = s.read_u8()
          data = s.read_u32()
        result.add(indent & "A: ")
        if ns != 0xffff_ffff'u32:
          result.add(pool[ns.int] & ":")
        result.add(pool[name])
        if name < resIDs.len:
          result.add("(0x" & resIDs[name].toHex & ")")
        result.add("=")
        case dataType
        of dtString.uint8:
          result.add("\"" & pool[data.int] & "\"")
        of dtInt.uint8:
          result.add($data)
        else:
          raise newException(ExpectationError, "unknown attribute type: 0x" & dataType.toHex)
        if raw != 0xffff_ffff'u32:
          result.add(" (Raw: \"" & pool[raw.int] & "\")")
        result.add("\n")
      indent.add("  ")
    of ctXMLEndElement:
      let
        ns = s.read_u32()
        name = s.read_u32().int
        top = stack.pop()
        wanted = "E " & ns.toHex & " " & name.toHex
      doAssert(top == wanted, $top & " != " & $wanted)
      indent.setLen(indent.len-4)
    else:
      raise newException(ExpectationError, "unexpected chunk type: 0x" & chunkType.toHex)
  if stack.len != 0:
    raise newException(ExpectationError, "unexpected non-empty stack: " & $stack)

using
  s: MarcoStream

proc read_u32(s): uint32 =
  let buf = s.Stream.readStr(4)
  if buf.len < 4:
    raise newException(ProtocolError, "expected 4 bytes for uint32, found only $# (hex $#)" % [$buf.len, toHex(buf)])
  return buf[0].uint32 * 0x00000001'u32 +
         buf[1].uint32 * 0x00000100'u32 +
         buf[2].uint32 * 0x00010000'u32 +
         buf[3].uint32 * 0x01000000'u32

proc read_u16(s): uint16 =
  let buf = s.Stream.readStr(2)
  if buf.len < 2:
    raise newException(ProtocolError, "expected 2 bytes for uint16, found only $# (hex $#)" % [$buf.len, toHex(buf)])
  return buf[0].uint16 * 0x0001'u16 +
         buf[1].uint16 * 0x0100'u16

proc read_u8(s): uint8 =
  let buf = s.Stream.readStr(1)
  if buf.len < 1:
    raise newException(ProtocolError, "expected 1 bytes for uint8, found only $# (hex $#)" % [$buf.len, toHex(buf)])
  return buf[0].uint8

proc expect(s; want: uint32) =
  let have = s.read_u32()
  if have != want:
    raise newException(ExpectationError, "expected $# (hex $#), got $# (hex $#)" % [$want, toHex(want), $have, toHex(have)])

proc expect(s; want: uint16) =
  let have = s.read_u16()
  if have != want:
    raise newException(ExpectationError, "expected $# (hex $#), got $# (hex $#)" % [$want, toHex(want), $have, toHex(have)])

proc expect(s; want: uint8) =
  let have = s.read_u8()
  if have != want:
    raise newException(ExpectationError, "expected $# (hex $#), got $# (hex $#)" % [$want, toHex(want), $have, toHex(have)])


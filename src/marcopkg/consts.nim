{.experimental: "codeReordering".}

type
  DataType* = enum
    dtString = 0x03,
    dtInt = 0x10

  ChunkType* = enum
    ctStringPool = 0x0001'u16
    ctXML = 0x0003'u16
    ctXMLStartNS = 0x0100'u16
    ctXMLEndNS = 0x0101'u16
    ctXMLStartElement = 0x0102'u16
    ctXMLEndElement = 0x0103'u16
    ctXMLResourceMap = 0x0180'u16


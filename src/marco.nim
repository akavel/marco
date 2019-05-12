{.experimental: "codeReordering".}
import streams
import xmlparser
import marcopkg/compile

# when isMainModule:

# stdout.write(marcoCompile(parseXml(newFileStream(stdin))))
stdout.write(stdin.newFileStream.parseXml.marcoCompile)

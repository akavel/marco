{.experimental: "codeReordering".}
import parseopt
import streams
import xmlparser
import marcopkg/compile

var
  input = stdin.newFileStream
  output = stdout.newFileStream

for kind, key, val in getopt():
  case key
  of "i": input = val.openFileStream(fmRead)
  of "o": output = val.openFileStream(fmWrite)
  else:
    stderr.write("unknown flag: " & key)
    quit(1)

# when isMainModule:

# stdout.write(marcoCompile(parseXml(newFileStream(stdin))))
output.write(input.parseXml.marcoCompile)

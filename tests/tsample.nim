{.experimental: "codeReordering".}
import unittest
import strutils
import re

import marcopkg / compile
import marcopkg / dump

test "AndroidManifest.xml based on czak/minimal-android-project":
  let compiled = marcoCompile"""
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.akavel.hello">
    <application android:label="HelloDali">
        <activity android:name="HelloActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
"""
  let expected = purgeLineMarkers"""
Binary XML
N: android=http://schemas.android.com/apk/res/android (line=2)
  E: manifest (line=2)
    A: http://schemas.android.com/apk/res/android:compileSdkVersion(0x01010572)=28
    A: http://schemas.android.com/apk/res/android:compileSdkVersionCodename(0x01010573)="9" (Raw: "9")
    A: package="com.akavel.hello" (Raw: "com.akavel.hello")
    A: platformBuildVersionCode=28 (Raw: "28")
    A: platformBuildVersionName=9 (Raw: "9")
      E: application (line=4)
        A: http://schemas.android.com/apk/res/android:label(0x01010001)="HelloDali" (Raw: "HelloDali")
          E: activity (line=5)
            A: http://schemas.android.com/apk/res/android:name(0x01010003)="HelloActivity" (Raw: "HelloActivity")
              E: intent-filter (line=6)
                  E: action (line=7)
                    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
                  E: category (line=8)
                    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")
"""
  check compiled.marcoDump == expected

proc strip_space(s: string): string =
  return s.multiReplace(("\n", ""), (" ", ""))

const HexChars = "0123456789ABCDEF"

proc dehexify(s: string): string =
  result = newString(s.len div 2)
  for i in 0 ..< s.len div 2:
    let chunk = s.substr(2 * i, 2 * i + 1)
    if chunk[0] == '.':
      result[i] = chunk[1]
    else:
      result[i] = parseHexStr(chunk)[0]

proc dumpHex(s: string): string =
  if s.len == 0: return ""
  let nlines = (s.len + 15) div 16
  const
    left = 3*8 + 2 + 3*8 + 2
    right = 16
    line = left+right+1
  result = ' '.repeat(nlines*line)
  for i, ch in s:
    let
      y = i div 16
      xr = i mod 16
      xl = if xr < 8: 3*xr else: 3*xr + 1
      n = ord(ch)
    result[y*line + xl] = HexChars[n shr 4]
    result[y*line + xl + 1] = HexChars[n and 0x0F]
    result[y*line + left + xr - 1] = if printable(ch): ch else: '.'
    if xr == 0:
      result[y*line + left + right - 1] = '\n'
  result = "\n " & result

func printable(c: char): bool =
  let n = ord(c)
  return 0x21 <= n and n <= 0x7E

func purgeLineMarkers(s: string): string {.inline.} =
  return s.replace(re(r" \(line=\d+\)$", {reStudy, reMultiLine}))


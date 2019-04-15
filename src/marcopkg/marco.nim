{.experimental: "codeReordering".}
import xmltools  # TODO: remove this dependency as it's too big & noisy

# References:
# - https://github.com/aosp-mirror/platform_frameworks_base/blob/e5cf74326dc37e87c24016640b535a269499e1ec/tools/aapt/XMLNode.cpp#L1089
# - https://android.googlesource.com/platform/frameworks/base/+/dc36bb6dea837608c29c177a7ea8cf46b6a0cd53/tools/aapt/XMLNode.cpp
# - https://github.com/sdklite/aapt/blob/9e6d1ad98469dffbc9940821551bd7a2e07dd1e0/src/main/java/com/sdklite/aapt/AssetEditor.java

proc marcoCompile*(inputXml: string): string =
  let xml = Node.fromStringE(inputXml)

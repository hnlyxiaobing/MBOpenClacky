#!/usr/bin/env bash
# Helper to run commands with MSVC Build Tools environment on Windows.
# Usage: source scripts/with_msvc_env.sh && moon test lib/web
#        scripts/with_msvc_env.sh moon build --target native --release cmd

export PATH='/c/Program Files (x86)/Microsoft Visual Studio/18/BuildTools/VC/Tools/MSVC/14.50.35717/bin/HostX64/x64:/c/Program Files (x86)/Microsoft Visual Studio/18/BuildTools/Common7/IDE/VC/VCPackages:/c/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64:'"$PATH"
export INCLUDE='C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\include;C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\ATLMFC\include;C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\VS\include;C:\Program Files (x86)\Windows Kits\10\include\10.0.26100.0\ucrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\um;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\shared;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\winrt;C:\Program Files (x86)\Windows Kits\10\\include\10.0.26100.0\\cppwinrt'
export LIB='C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\ATLMFC\lib\x64;C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\lib\x64;C:\Program Files (x86)\Windows Kits\10\lib\10.0.26100.0\ucrt\x64;C:\Program Files (x86)\Windows Kits\10\\lib\10.0.26100.0\\um\x64'
export LIBPATH='C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\ATLMFC\lib\x64;C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\lib\x64;C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\lib\x86\store\references;C:\Program Files (x86)\Windows Kits\10\UnionMetadata\10.0.26100.0;C:\Program Files (x86)\Windows Kits\10\References\10.0.26100.0;C:\Windows\Microsoft.NET\Framework64\v4.0.30319'
export UCRTVersion='10.0.26100.0'
export UniversalCRTSdkDir='C:\Program Files (x86)\Windows Kits\10\\'
export VCToolsInstallDir='C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\\'
export WindowsSdkDir='C:\Program Files (x86)\Windows Kits\10\\'
export WindowsSDKVersion='10.0.26100.0\\'

if [ $# -gt 0 ]; then
  exec "$@"
fi

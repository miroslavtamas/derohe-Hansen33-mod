#!/usr/bin/env bash

package=$1
# basename is portable across macOS bash 3.2 (no [-1] array indexing) and bash 4+.
package_name=$(basename "$package")


CURDIR=`/bin/pwd`
BASEDIR=$(dirname $0)
ABSPATH=$(readlink -f $0)
ABSDIR=$(dirname $ABSPATH)


PLATFORMS="darwin/arm64" # amd64/arm64 only as of go1.16
#PLATFORMS="$PLATFORMS windows/amd64" # arm compilation not available for Windows
PLATFORMS="$PLATFORMS linux/amd64"
PLATFORMS="$PLATFORMS linux/arm64"
#PLATFORMS="$PLATFORMS linux/ppc64le"   is it common enough ??
#PLATFORMS="$PLATFORMS linux/mips64le" # experimental in go1.6 is it common enough ??
#PLATFORMS="$PLATFORMS freebsd/amd64"
#PLATFORMS="$PLATFORMS freebsd/arm64"
#PLATFORMS="$PLATFORMS netbsd/amd64" # amd64 only as of go1.6
#PLATFORMS="$PLATFORMS openbsd/amd64" # amd64 only as of go1.6
#PLATFORMS="$PLATFORMS dragonfly/amd64" # amd64 only as of go1.5
#PLATFORMS="$PLATFORMS plan9/amd64 plan9/386" # as of go1.4, is it common enough ??
# solaris disabled due to badger  error below
#vendor/github.com/dgraph-io/badger/y/mmap_unix.go:57:30: undefined: syscall.SYS_MADVISE
#PLATFORMS="$PLATFORMS solaris/amd64" # as of go1.3


#PLATFORMS_ARM="linux freebsd netbsd"
PLATFORMS_ARM="linux"


#PLATFORMS="linux/amd64"
#PLATFORMS_ARM=""

# dero-miner uses cgo to call vendored libsais (~35% faster PoW than the
# pure-Go SA-IS fallback). Cross-compiling cgo needs a C toolchain for the
# target. The simplest portable option is `zig cc` (a single zig install
# handles every target). If zig is on PATH we use it for cross builds;
# otherwise the build falls back to CGO_ENABLED=0 for that target and the
# !cgo branch in sa_libsais_nocgo.go takes over. The binary is still
# correct, just slower.
USE_CGO=0
if [[ "${package_name}" == "dero-miner" ]]; then
  USE_CGO=1
fi

HAS_ZIG=0
if command -v zig >/dev/null 2>&1; then
  HAS_ZIG=1
fi

HOST_GOOS=$(go env GOOS)
HOST_GOARCH=$(go env GOARCH)

# Map a Go GOOS/GOARCH pair to the matching `zig cc -target` triple.
zig_target() {
  local goos=$1
  local goarch=$2
  local goarm=$3
  local arch
  case "$goarch" in
    amd64) arch=x86_64 ;;
    arm64) arch=aarch64 ;;
    arm)   arch=arm ;;
    386)   arch=i386 ;;
    *)     arch="$goarch" ;;
  esac
  case "$goos" in
    linux)
      if [[ "$goarch" == "arm" ]]; then
        # GOARM=7 maps to armv7 + hard float
        echo "${arch}-linux-musleabihf"
      else
        echo "${arch}-linux-musl"
      fi
      ;;
    darwin)  echo "${arch}-macos-none" ;;
    windows) echo "${arch}-windows-gnu" ;;
    freebsd) echo "${arch}-freebsd-none" ;;
    *)       echo "" ;;
  esac
}

# Emit the env-var prefix needed to drive `go build` for one target.
# Sets CGO_ENABLED, GOOS, GOARCH, and (when needed) CC/CXX. Prints a
# warning to stderr when falling back to CGO_ENABLED=0.
build_env() {
  local goos=$1
  local goarch=$2
  local goarm=$3
  local label="${goos}/${goarch}${goarm:+${goarm}}"
  if [[ "${USE_CGO}" != "1" ]]; then
    # Non-miner packages: preserve original behaviour — force static
    # linux/amd64 with CGO_ENABLED=0, otherwise use the host default.
    if [[ "${goos}" == "linux" && "${goarch}" == "amd64" ]]; then
      echo "CGO_ENABLED=0 GOOS=${goos} GOARCH=${goarch}${goarm:+ GOARM=${goarm}}"
    else
      echo "GOOS=${goos} GOARCH=${goarch}${goarm:+ GOARM=${goarm}}"
    fi
    return
  fi
  # Miner package: try to keep cgo on so libsais ships in the binary.
  if [[ "${goos}" == "${HOST_GOOS}" && "${goarch}" == "${HOST_GOARCH}" ]]; then
    echo "CGO_ENABLED=1 GOOS=${goos} GOARCH=${goarch}${goarm:+ GOARM=${goarm}}"
    return
  fi
  if [[ "${HAS_ZIG}" == "1" ]]; then
    local ztgt
    ztgt=$(zig_target "${goos}" "${goarch}" "${goarm}")
    if [[ -n "${ztgt}" ]]; then
      echo "CGO_ENABLED=1 CC=\"zig cc -target ${ztgt}\" CXX=\"zig c++ -target ${ztgt}\" GOOS=${goos} GOARCH=${goarch}${goarm:+ GOARM=${goarm}}"
      return
    fi
    echo "WARN: no zig target mapping for ${label}; using pure-Go SA-IS fallback (slower miner)" >&2
  else
    echo "WARN: ${label} cross-build without zig; using pure-Go SA-IS fallback (slower miner). Install zig for cgo cross-builds." >&2
  fi
  echo "CGO_ENABLED=0 GOOS=${goos} GOARCH=${goarch}${goarm:+ GOARM=${goarm}}"
}


type setopt >/dev/null 2>&1

SCRIPT_NAME=`basename "$0"`
FAILURES=""
CURRENT_DIRECTORY=${PWD##*/}
OUTPUT="$package_name" # if no src file given, use current dir name

GCFLAGS=""
#if [[ "${OUTPUT}" == "dero-miner" ]]; then GCFLAGS="github.com/deroproject/derohe/astrobwt=-B"; fi

for PLATFORM in $PLATFORMS; do
  GOOS=${PLATFORM%/*}
  GOARCH=${PLATFORM#*/}
  OUTPUT_DIR="${ABSDIR}/build/dero_${GOOS}_${GOARCH}"
  BIN_FILENAME="${OUTPUT}-${GOOS}-${GOARCH}"
  echo  mkdir -p $OUTPUT_DIR
  if [[ "${GOOS}" == "windows" ]]; then BIN_FILENAME="${BIN_FILENAME}.exe"; fi
  ENV_PREFIX=$(build_env "${GOOS}" "${GOARCH}" "")
  CMD="${ENV_PREFIX} go build -trimpath -ldflags=-buildid= -gcflags=${GCFLAGS} -o $OUTPUT_DIR/${BIN_FILENAME} $package"
  echo "${CMD}"
  eval $CMD || FAILURES="${FAILURES} ${PLATFORM}"

  # build docker image for linux amd64 competely static
  #if [[ "${GOOS}" == "linux" && "${GOARCH}" == "amd64" && "${OUTPUT}" != "explorer" && "${OUTPUT}" != "dero-miner" ]] ; then
  #  BIN_FILENAME="docker-${OUTPUT}-${GOOS}-${GOARCH}"
  #  CMD="GOOS=${GOOS} GOARCH=${GOARCH} CGO_ENABLED=0 go build -o $OUTPUT_DIR/${BIN_FILENAME} $package"
  #  echo "${CMD}"
  #  eval $CMD || FAILURES="${FAILURES} ${PLATFORM}"
  #fi


done


for GOOS in $PLATFORMS_ARM; do
  GOARCH="arm"
  # build for each ARM version
#  for GOARM in 7 6 5; do
   for GOARM in 7; do
    OUTPUT_DIR="${ABSDIR}/build/dero_${GOOS}_${GOARCH}${GOARM}"
    BIN_FILENAME="${OUTPUT}-${GOOS}-${GOARCH}${GOARM}"
    ENV_PREFIX=$(build_env "${GOOS}" "${GOARCH}" "${GOARM}")
    CMD="${ENV_PREFIX} go build -trimpath -ldflags=-buildid= -gcflags=${GCFLAGS} -o $OUTPUT_DIR/${BIN_FILENAME} $package"
    echo "${CMD}"
    eval "${CMD}" || FAILURES="${FAILURES} ${GOOS}/${GOARCH}${GOARM}"
  done
done

# eval errors
if [[ "${FAILURES}" != "" ]]; then
  echo ""
  echo "${SCRIPT_NAME} failed on: ${FAILURES}"
  exit 1
fi

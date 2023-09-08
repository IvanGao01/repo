#!/bin/bash
set -e

NAME=""
OUTPUT=""
BUILD_OPTION=""
VERSION=""

USER=cnosdb
GROUP=cnosdb
DESCRIPTION="An Open Source Distributed Time Series Database with high performance, high compression ratio and high usability."
LICENSE="AGPL-3.0"
VENDOR="CnosDB Tech (Beijing) Limited"
MAINTAINER="CnosDB Team"
WEBSITE="https://www.cnosdb.com/"
LOG_DIR="/var/log/cnosdb"
DATA_DIR="/var/lib/cnosdb"

usage() {
cat << EOF
Usage: $0 -n <package-name> -v <version> [[-o <PATH>] [-l] [-N] [-r] [-h]

Build and upload packages.

Options:
  -n <package-name>   The name of the package to build. Required.
  -v <version>        The version of the package to build. Required.
  -o <PATH>           Path to output package. Optional.
  -b <BUILD OPTION>   Build option [latest, nightly, release]. Optional. Default is release.
  -h                  Show this help message.
EOF
}

# 解析命令行选项和参数
while getopts "n:s:i:k:o:b:h" opt; do
  case ${opt} in
    n) NAME=$OPTARG ;;
    v) VERSION=$OPTARG;;
    o) OUTPUT=$OPTARG;;
    b) BUILD_OPTION=$OPTARG ;;
    h) usage; exit 0 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
  esac
done

# Verify if necessary parameters exist
if [ -z "$NAME" ]; then
  echo "Package name is missing! Use -n option to specify the package name."
  usage
  exit 1
fi

# Verify if BUILD_OPTION is legal
if [ "$BUILD_OPTION" != "latest" ] && [ "$BUILD_OPTION" != "nightly" ] && [ "$BUILD_OPTION" != "release" ]; then
  echo "Build option is invalid! Use -b option to specify the build option."
  usage
  exit 1
fi

# If BUILD_OPTION is not equal to release, then use nightly or latest directly
if [ "$BUILD_OPTION" != "release" ]; then
  VERSION="$BUILD_OPTION"
fi

# 获取当前Git仓库的基本名称
repo_name=$(basename $(git rev-parse --show-toplevel))

# 根据仓库名称设置version变量
if [ "$repo_name" = "cnosdb" ]; then
  VERSION=${VERSION}"-community"
elif [ "$repo_name" = "cnosdb-enterprise" ]; then
  VERSION=${VERSION}"-enterprise"
else
  echo "Not a valid repo."
  exit 1
fi

## Receive the NAME parameter and specify different FPMs based on different FPM_CMD String
build_fpm_cmd() {

NAME=$1
OUTPUT_TYPE=$3
TARGET=$4

PKG_TEMP=$(mktemp -d)

   # Create layout for packaging under $PKG_TEMP.
  mkdir -p "${PKG_TEMP}/usr/bin" \
           "${PKG_TEMP}/var/log/cnosdb" \
           "${PKG_TEMP}/var/lib/cnosdb" \
           "${PKG_TEMP}/etc/cnosdb" \
           "${PKG_TEMP}/usr/lib/${NAME}/scripts"

  # Copy service scripts.
  cp "/cnosdb/scripts/package/${NAME}/init.sh" "${PKG_TEMP}/usr/lib/${NAME}/scripts/init.sh"
  chmod 0644 "${PKG_TEMP}/usr/lib/${NAME}/scripts/init.sh"
  cp "/cnosdb/scripts/package/${NAME}/${NAME}.service" "${PKG_TEMP}/usr/lib/${NAME}/scripts/${NAME}.service"
  chmod 0644 "${PKG_TEMP}/usr/lib/${NAME}/scripts/${NAME}.service"

  if [ "${NAME}" == "cnosdb" ]; then

      cp /cnosdb/config/config.toml "${PKG_TEMP}/etc/${NAME}/${NAME}.conf"

      # Copy binaries.
      cp "/cnosdb/target/${TARGET}/release/cnosdb" "${PKG_TEMP}/usr/bin/cnosdb"
      cp "/cnosdb/target/${TARGET}/release/cnosdb-cli" "${PKG_TEMP}/usr/bin/cnosdb-cli"

      chmod 755 "${PKG_TEMP}/usr/bin/cnosdb"
      chmod 755 "${PKG_TEMP}/usr/bin/cnosdb-cli"

  elif [ "${NAME}" == "cnosdb-meta" ]; then

      cp /cnosdb/meta/config/config.toml "${PKG_TEMP}/etc/cnosdb/${NAME}.conf"

      cp "/cnosdb/target/${TARGET}/release/cnosdb-meta" "${PKG_TEMP}/usr/bin/cnosdb-meta"

      chmod 755 "${PKG_TEMP}/usr/bin/cnosdb-meta"

  else
      echo "Invalid build name."
  fi

  chmod 0644 "${PKG_TEMP}/etc/cnosdb/${NAME}.conf"



   PACKAGE_NAME=$(fpm -t "${OUTPUT_TYPE}" \
   -C "${PKG_TEMP}" \
   -n "${NAME}" \
   -v "${VERSION}" \
   --architecture "${ARCH}" \
   -s dir \
   --url "https://www.cnosdb.com/" \
   --before-install /cnosdb/scripts/package/"${NAME}"/before-install.sh \
   --after-install /cnosdb/scripts/package/"${NAME}"/after-install.sh \
   --after-remove /cnosdb/scripts/package/"${NAME}"/after-remove.sh \
   --directories "${LOG_DIR}" \
   --directories "${DATA_DIR}" \
   --rpm-attr 755,${USER},${GROUP}:${LOG_DIR} \
   --rpm-attr 755,${USER},cnosdb:"${DATA_DIR}" \
   --config-files /etc/cnosdb/${NAME}.conf \
   --maintainer "CnosDB Team" \
   --vendor "CnosDB Tech (Beijing) Limited" \
   --license ${LICENSE} \
   --description "An Open Source Distributed Time Series Database with high performance, high compression ratio and high usability." \
   --iteration 1 | ruby -e 'puts (eval ARGF.read)[:path]')

   echo "${PACKAGE_NAME}"
}


main(){
  if [[ ${TARGET} == "x86_64-unknown-linux-gnu" ]]; then
      ARCH="x86_64"
  elif [[ ${TARGET} == "aarch64-unknown-linux-gnu" ]]; then
      ARCH="arm64"
  fi


  output_types=["deb","rpm"]
  for output_type in "${output_types[@]}"; do
    if [ "${target}" == "x86_64-unknown-linux-gnu" ];then
      arch=amd64
    elif [ "${target}" == "aarch64-unknown-linux-gnu" ];then
      arch=arm64
     fi
   # Call the build_fpm_cmd function with the given arguments
   build_fpm_cmd "${NAME}" "${arch}" "${output_type}" "${target}"
  done
}

main
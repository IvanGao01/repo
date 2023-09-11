#!/bin/bash
set -e

# 默认值
NAME=""
BUILD_OPTION=""
VERSION=""
TARGET=""

USER=cnosdb
GROUP=cnosdb
DESCRIPTION="An Open Source Distributed Time Series Database with high performance, high compression ratio and high usability."
LICENSE="AGPL-3.0"
VENDOR="CnosDB Tech (Beijing) Limited"
MAINTAINER="CnosDB Team"
WEBSITE="https://www.cnosdb.com/"
LOG_DIR="/var/log/cnosdb"
DATA_DIR="/var/lib/cnosdb"

# 帮助函数
usage() {
  cat << EOF
Usage: $0 -n <package-name> -v <version> [[-t <target>] [-b <BUILD_OPTION>] [-h]]

Build and upload packages.

Options:
  -n <package-name>   The name of the package to build. Required.
  -v <version>        The version of the package to build. Required.
  -t <target>         The binary of the target. Required.
  -b <BUILD_OPTION>   Build option [latest, nightly, release]. Optional. Default is release.
  -h                  Show this help message.
EOF
}

# 解析命令行选项和参数
while getopts "n:v:t:b:h" opt; do
  case ${opt} in
    n) NAME=$OPTARG ;;
    v) VERSION=$OPTARG ;;
    t) TARGET=$OPTARG ;;
    b) BUILD_OPTION=$OPTARG ;;
    h) usage; exit 0 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
  esac
done

# 验证必要参数是否存在
if [ -z "$NAME" ]; then
  echo "Package name is missing! Use -n option to specify the package name."
  usage
  exit 1
fi

# 验证构建选项是否合法
if [ "$BUILD_OPTION" != "latest" ] && [ "$BUILD_OPTION" != "nightly" ] && [ "$BUILD_OPTION" != "release" ]; then
  echo "Build option is invalid! Use -b option to specify the build option."
  usage
  exit 1
fi

# 如果BUILD_OPTION不等于release，则直接使用nightly或latest
if [ "$BUILD_OPTION" != "release" ]; then
  VERSION="$BUILD_OPTION"
fi

# 获取当前Git Repo的基本名称
get_repo_name() {
  local repo_path=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$repo_path" ]; then
    echo $(basename "$repo_path")
  else
    echo ""
  fi
}

repo_name=$(get_repo_name)

# 根据repo_name设置版本变量
set_version_based_on_repo() {
  if [ "$repo_name" = "repo" ]; then
    VERSION=${VERSION}"-community"
  elif [ "$repo_name" = "cnosdb-enterprise" ]; then
    VERSION=${VERSION}"-enterprise"
  else
    echo "Not a valid repo."
    exit 1
  fi
}

set_version_based_on_repo

# 构建FPM命令并打包
build_fpm_cmd() {
  local name="$1"
  local arch="$2"
  local output_type="$3"
  local target="$4"
  local pkg_temp=$(mktemp -d)

  # 创建打包布局
  mkdir -p "${pkg_temp}/usr/bin" \
           "${pkg_temp}/var/log/cnosdb" \
           "${pkg_temp}/var/lib/cnosdb" \
           "${pkg_temp}/etc/cnosdb" \
           "${pkg_temp}/usr/lib/${name}/scripts"

  # 复制服务脚本
  cp "./releng/scripts/${name}/init.sh" "${pkg_temp}/usr/lib/${name}/scripts/init.sh"
  chmod 0644 "${pkg_temp}/usr/lib/${name}/scripts/init.sh"
  cp "./releng/scripts/${name}/${name}.service" "${pkg_temp}/usr/lib/${name}/scripts/${name}.service"
  chmod 0644 "${pkg_temp}/usr/lib/${name}/scripts/${name}.service"

  if [ "${name}" == "cnosdb" ]; then
    cp ./config/config.toml "${pkg_temp}/etc/${name}/${name}.conf"

    # 复制二进制文件
    cp "./target/${target}/release/cnosdb" "${pkg_temp}/usr/bin/cnosdb"
    cp "./target/${target}/release/cnosdb-cli" "${pkg_temp}/usr/bin/cnosdb-cli"
    cp "./target/${target}/release/inspect" "${pkg_temp}/usr/bin/inspect"

    chmod 755 "${pkg_temp}/usr/bin/cnosdb"
    chmod 755 "${pkg_temp}/usr/bin/cnosdb-cli"
    chmod 755 "${pkg_temp}/usr/bin/inspect"
  elif [ "${name}" == "cnosdb-meta" ]; then
    cp ./meta/config/config.toml "${pkg_temp}/etc/cnosdb/${name}.conf"
    cp "./target/${target}/release/cnosdb-meta" "${pkg_temp}/usr/bin/cnosdb-meta"
    chmod 755 "${pkg_temp}/usr/bin/cnosdb-meta"
  else
    echo "Invalid build name."
  fi

  chmod 0644 "${pkg_temp}/etc/cnosdb/${name}.conf"

  # 构建包并返回包名
  local package_name=$(fpm -t "${output_type}" \
                         -C "${pkg_temp}" \
                         -n "${name}" \
                         -v "${VERSION}" \
                         --architecture "${arch}" \
                         -s dir \
                         --url "${WEBSITE}" \
                         --before-install ./releng/scripts/"${name}"/before-install.sh \
                         --after-install ./releng/scripts/"${name}"/after-install.sh \
                         --after-remove ./releng/scripts/"${name}"/after-remove.sh \
                         --directories "${LOG_DIR}" \
                         --directories "${DATA_DIR}" \
                         --rpm-attr 755,${USER},${GROUP}:${LOG_DIR} \
                         --rpm-attr 755,${USER},cnosdb:"${DATA_DIR}" \
                         --config-files /etc/cnosdb/${name}.conf \
                         --maintainer "${MAINTAINER}" \
                         --vendor "${VENDOR}" \
                         --license "${LICENSE}" \
                         --description "${DESCRIPTION}" \
                         --iteration 1 | ruby -e 'puts (eval ARGF.read)[:path]')

  echo "${package_name}"
}

# 主函数
main() {
  ARCH=""

  if [[ ${TARGET} == "x86_64-unknown-linux-gnu" ]]; then
    ARCH="x86_64"
  elif [[ ${TARGET} == "aarch64-unknown-linux-gnu" ]]; then
    ARCH="arm64"
  else
    echo "Unknown target: $TARGET"
  fi

  output_types=("deb" "rpm")
  for output_type in "${output_types[@]}"; do
    # 调用build_fpm_cmd函数并传递参数
    build_fpm_cmd "${NAME}" "${ARCH}" "${output_type}" "${TARGET}"
  done
}

# 执行主函数
main
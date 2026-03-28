#!/usr/bin/env bash

read_app_version() {
  local root_dir="$1"
  local version_file="${VERSION_FILE:-$root_dir/version.txt}"

  if [[ -n "${APP_VERSION:-}" ]]; then
    printf '%s\n' "$APP_VERSION"
    return 0
  fi

  if [[ -f "$version_file" ]]; then
    tr -d '\r\n' < "$version_file"
    return 0
  fi

  printf '\n'
}

update_readme_version() {
  local root_dir="$1"
  local app_version="${2:-$(read_app_version "$root_dir")}"
  local readme_path="${README_FILE:-$root_dir/README.md}"

  if [[ -z "$app_version" || ! -f "$readme_path" ]]; then
    return 0
  fi

  sed -i.bak \
    -e "s/^Version: .*/Version: $app_version/" \
    -e "s/^Beta v.*/Version: $app_version/" \
    "$readme_path"
  rm -f "${readme_path}.bak"
}

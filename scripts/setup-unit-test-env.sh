#!/usr/bin/env bash
# Enhanced Cooldown Manager addon for World of Warcraft
# Author: Argium
# Licensed under the GNU General Public License v3.0

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ "${EUID}" -eq 0 ]]; then
    sudo_cmd=()
elif command -v sudo >/dev/null 2>&1; then
    sudo_cmd=(sudo)
else
    echo "Root privileges or sudo are required to install apt packages." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

"${sudo_cmd[@]}" apt-get update
"${sudo_cmd[@]}" apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    liblua5.1-0-dev \
    lua5.1 \
    luarocks

"${sudo_cmd[@]}" luarocks --lua-version=5.1 install moonscript 0.6.0-1
"${sudo_cmd[@]}" luarocks --lua-version=5.1 install busted 2.3.0-1
"${sudo_cmd[@]}" luarocks --lua-version=5.1 install luacov 0.17.0-1
"${sudo_cmd[@]}" luarocks --lua-version=5.1 install luacheck 1.2.0-1
"${sudo_cmd[@]}" luarocks --lua-version=5.1 install luacov-html 1.0.0-1

# External libraries are intentionally not downloaded by default.
# Uncomment this block if the Codex setup phase should vendor .pkgmeta externals before sandboxing.
#
# "${sudo_cmd[@]}" apt-get install -y --no-install-recommends subversion unzip
#
# fetch_root="$(mktemp -d)"
# trap 'rm -rf "$fetch_root"' EXIT
#
# fetch_svn_external() {
#     local url="$1"
#     local target="$2"
#
#     rm -rf "$target"
#     mkdir -p "$(dirname "$target")"
#     svn export --force "$url" "$target"
# }
#
# fetch_github_tag() {
#     local owner_repo="$1"
#     local tag="$2"
#     local target="$3"
#     local repo="${owner_repo##*/}"
#     local zip_file="$fetch_root/${repo}.zip"
#     local extract_dir="$fetch_root/${repo}"
#     local entries
#
#     rm -rf "$target" "$extract_dir"
#     mkdir -p "$(dirname "$target")" "$extract_dir"
#     curl -fsSL "https://codeload.github.com/${owner_repo}/zip/refs/tags/${tag}" -o "$zip_file"
#     unzip -q "$zip_file" -d "$extract_dir"
#
#     entries=("$extract_dir"/*)
#     if [[ "${#entries[@]}" -ne 1 || ! -d "${entries[0]}" ]]; then
#         echo "Unexpected archive layout for ${owner_repo}@${tag}" >&2
#         exit 1
#     fi
#
#     mv "${entries[0]}" "$target"
# }
#
# fetch_svn_external https://repos.wowace.com/wow/libstub/trunk Libs/LibStub
# fetch_svn_external https://repos.wowace.com/wow/callbackhandler/trunk/CallbackHandler-1.0 Libs/CallbackHandler-1.0
# fetch_svn_external https://repos.wowace.com/wow/ace3/trunk/AceAddon-3.0 Libs/AceAddon-3.0
# fetch_svn_external https://repos.wowace.com/wow/ace3/trunk/AceDB-3.0 Libs/AceDB-3.0
# fetch_svn_external https://repos.wowace.com/wow/libsharedmedia-3-0/trunk/LibSharedMedia-3.0 Libs/LibSharedMedia-3.0
# fetch_github_tag SafeteeWoW/LibDeflate 1.0.2-release Libs/LibDeflate
# fetch_github_tag p3lim-wow/LibEditMode 15 Libs/LibEditMode
# fetch_github_tag rossnichols/LibSerialize v1.2.1 Libs/LibSerialize

cat <<'EOF'

Setup complete.

After sandboxing, run:

  busted Tests
  busted --run libsettingsbuilder
  busted --run libconsole
  busted --run libevent
  busted --run liblsmsettingswidgets
  luacheck . -q

EOF

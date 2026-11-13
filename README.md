# Patched ONLYOFFICE Docs Community 10.0.0

This repository contains the complete set of changes Amplytic applies to
ONLYOFFICE Docs Community Edition `v10.0.0.169`, and the scripts that build
the image Amplytic runs. ONLYOFFICE Docs is licensed under AGPL-3.0. This
repository is the source offer for that modified build.

We run this build until ONLYOFFICE publishes a Community release with the same
fixes. We then return to the official image.

## Changes from upstream

The build uses the upstream source at tag `v10.0.0.169` and changes three
things:

| Upstream | This build | Why |
| --- | --- | --- |
| `build_tools/scripts/build_server.py`: `pkg_target = "node20"` | `"node24"` | Node.js 20 is end of life |
| `build_tools/tools/linux/deps.py` installs `@yao-pkg/pkg@6.11.0` | `build-in-container.sh` installs `@yao-pkg/pkg@6.25.0` | 6.25.0 embeds Node.js v24.22.1 |
| `core/Common/3dParty/brotli/make.py` pins google/brotli `a47d7475` (1.1.0) | pins `db24a98a` (v1.2.1) | CVE-2026-111497 |

Two further changes let the published build run today. Neither changes what
ships:

- `build_tools/scripts/core_common/modules/v8_89.py` pins depot_tools to
  `a03dfbf7`.
- `fetch v8` uses the system Python (`DEPOT_TOOLS_BOOTSTRAP_PYTHON3=0`).

The exact diffs against upstream are in `patches/`. The image is built with
the Dockerfile from ONLYOFFICE/Docker-DocumentServer at tag `v10.0.0.169`
(`839b73b568db94d117fdeaf3374f55f78ee9b1db`), unmodified.

## Upstream source

Every other file is the unmodified upstream source.
`provenance.txt` lists the exact commit of each repository that went into
the build. All of them are public under https://github.com/ONLYOFFICE, except
two third-party dependencies, which are public elsewhere:

- google/brotli at `db24a98aed38a16de78cc05ca15cdd8dc2a0d92d` (https://github.com/google/brotli)
- Chromium depot_tools at `a03dfbf7f2d1cefa2795d81d59ca4f16c8616a8f` (https://chromium.googlesource.com/chromium/tools/depot_tools)

## Build

Run on a Linux x86_64 host with Docker, at least 8 vCPU and about 100 GB of
free disk:

    WORK_DIR=$HOME/oo-fork ./build.sh

`build.sh` compiles inside `ubuntu:24.04`, packages a `.deb`, builds the
image, and runs `verify.sh`, which checks the Node.js version embedded in the
server binaries.

## License

ONLYOFFICE Docs and the patches in `patches/` are licensed under
AGPL-3.0. See https://github.com/ONLYOFFICE/DocumentServer/blob/master/LICENSE.txt.

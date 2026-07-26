# gcc-arm-none-eabi (conda package)

Builds the [Arm GNU Toolchain](https://developer.arm.com/Tools%20and%20Software/GNU%20Toolchain)
(`arm-none-eabi` GCC, binutils, newlib, newlib-nano and GDB for bare-metal Arm
targets) as a relocatable conda package with [rattler-build](https://rattler.build),
for `linux-64`, `linux-aarch64` and `osx-arm64`. (`osx-64` does not fit the
6-hour GitHub-hosted runner ceiling; an attempt to close the gap with ccache
lives on the `osx-64-ccache` branch.)

The toolchain is compiled **from source** — from Arm's official source snapshot,
using Arm's own build scripts
([gnu-devtools-for-arm](https://gitlab.arm.com/tooling/gnu-devtools-for-arm)) —
rather than repackaging Arm's prebuilt binary release. Binary repackaging is
what blocked the earlier conda-forge attempt
([staged-recipes#32671](https://github.com/conda-forge/staged-recipes/pull/32671)),
along with the prebuilt `arm-none-eabi-gdb-py` linking a Python from outside the
conda environment.

## Using the toolchain with Pixi

```toml
[workspace]
channels = ["https://prefix.dev/eliacereda", "conda-forge"]
platforms = ["linux-64", "linux-aarch64", "osx-arm64"]

[dependencies]
gcc-arm-none-eabi = "15.2.*"
```

Then `pixi install` and `arm-none-eabi-gcc` is on the environment path.
For ad-hoc use: `pixi global install -c https://prefix.dev/eliacereda gcc-arm-none-eabi`.

### Version numbering

Arm names its releases `15.2.rel1`, which is not a usable conda version: the
`.rel1` segment sorts unpredictably against a future `15.3.rel1` and confuses
`>=15.2`-style specs. The package maps them to plain three-part versions:

| Arm release | conda version |
| --- | --- |
| `15.2.rel1` | `15.2.1` |

The Arm release name is kept in `context.arm_release` in the recipe and is what
builds the source download URL. Recipe-only respins bump `build.number`.

## What this build includes

- **R/M-profile multilibs only** (`--with-multilib-list=rmprofile`) — Cortex-M
  and Cortex-R. A-profile multilibs roughly double an already multi-hour build
  and would not fit in a GitHub-hosted runner's 6-hour ceiling. Run
  `arm-none-eabi-gcc -print-multi-lib` to see the exact list. If you need
  Cortex-A bare-metal support, open an issue.
- **newlib and newlib-nano**, so both `--specs=nano.specs` and the full newlib
  are available.
- **Target libraries stripped of heavy debug sections**, exactly as Arm's own
  releases are (their `strip_lib` packaging step): `.debug_frame` is kept so
  stack unwinding through libc/libstdc++ works, but source-level stepping into
  the libraries is not available. This is what keeps the packages ~4x smaller
  than a full-DWARF build.
- **GDB without Python support.** Linking conda's Python would add a runtime
  dependency and recreate the portability problem that sank the earlier
  conda-forge submission; the host binaries here depend on glibc alone. This
  means no `arm-none-eabi-gdb-py` and no Python pretty-printers.

## Building locally

```sh
pixi run build
```

This runs `rattler-build build --recipe recipe/recipe.yaml`. Expect a **long**
build — several hours, dominated by building libgcc/newlib once per multilib.
The build is fully conda-native: compilers (`${{ compiler('c') }}`, conda-forge
gcc 13 with the glibc 2.28 sysroot — see [recipe/variants.yaml](recipe/variants.yaml))
and all build tools come from conda-forge, so it works on any Linux host with no
container and no distro packages, and the package's `__glibc >=2.28` floor comes
from the pinned sysroot rather than from the build machine.

### How the source tree is assembled

Two sources are combined by the recipe into the layout Arm's scripts require:

```
$SRC_DIR/src/
  gnu-devtools-for-arm/     <- git, pinned tag (MIT)
  gcc/  binutils-gdb/  newlib-cygwin/  gmp/  mpfr/  mpc/  isl/  libexpat/  ...
                            <- Arm's source snapshot tarball
```

[recipe/build.sh](recipe/build.sh) then calls `build-baremetal-toolchain.sh`
directly rather than going through the `build-gnu-toolchain.sh` wrapper: the
wrapper treats everything after `--` as *make targets* rather than as flags for
the lower-level script, so the `-- --release --enable-newlib-nano` form shown in
Arm's README does not do what it appears to. The flags in `build.sh` reproduce
what the wrapper generates for `--target=arm-none-eabi --rmprofile`.

The install location is passed through the `installdir` / `prefix` environment
variables, which is the only interface the script offers for it. GCC is
configured with an absolute `--prefix="$installdir"`, so the toolchain installs
straight into the conda build prefix.

## CI and publishing

GitHub Actions ([.github/workflows/conda.yml](.github/workflows/conda.yml)) builds
every platform natively on hosted runners (`ubuntu-24.04`, `ubuntu-24.04-arm`,
`macos-15`) on every push/PR. Pushing a `v*` tag additionally uploads the packages to the
`eliacereda` channel on prefix.dev, authenticating via OIDC trusted publishing
(the repository is registered as a Trusted Publisher on prefix.dev; no stored
API key).

Release flow: bump `context.version` / `context.arm_release` (and
`context.devtools_rev` if appropriate) in the recipe, tag `v<version>`
(e.g. `v15.2.1`), push the tag.

Note that CI runs close to the runner time limit. If a build starts timing out,
the options are to cut the multilib list further, or move to a self-hosted
runner.

## Notes on relocatability

The package ships the toolchain with its build-time installation prefix left
untouched inside the ELF binaries (`prefix_detection: ignore_binary_files`):
that path never exists at install time, so GCC's own `argv[0]`-relative
self-relocation resolves every internal path. Rewriting the embedded prefix
instead would corrupt the driver, because GCC constant-folds `strlen` of the
compiled-in prefix into fixed offsets at build time.

To verify this after a build, install the package into a prefix at a *different*
path than it was built in and compile something — a
`<prefix>/lib/gcc/: Is a directory` error is the signature of prefix handling
gone wrong.

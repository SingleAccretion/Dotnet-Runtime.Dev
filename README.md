## Dotnet-Runtime.Dev

This repository is a collection of scripts, along with the corresponding directory structure, used by the author for his work on [dotnet/runtime](https://github.com/dotnet/runtime) changes, specifically to the RyuJit compiler, using Visual Studio on Windows (10+).

### How can one take advantage of it?

This repository provides a "skeleton", so many of the pieces have to be filled in manually before the scripts can be used.

Note: throughout this document, `$REPO_ROOT` will refer to the directory into which this reposirty was cloned (`C:\Users\Accretion\source\dotnet` for the author).

#### Installation-wide dependencies

1) [Powershell 7+](https://github.com/PowerShell/PowerShell).
2) [Visual Studio 2022](https://visualstudio.microsoft.com/vs/) and [all other prerequisites for bulding dotnet/runtime](https://github.com/dotnet/runtime/blob/main/docs/workflow/requirements/windows-requirements.md).
3) [Cygwin](https://www.cygwin.com/), for building PIN.
4) Fully built https://github.com/dotnet/jitutils.
5) The following environment variables:
   - `SUPERPMI_CACHE_DIRECTORY` = `$REPO_ROOT/diffs/spmi`.
   - `PATH` should include `$REPO_ROOT/diffs` and `jitutils/bin`.
6) A remote (GH) fork of `dotnet/runtime`.
7) TODO: document things required for working with the RyuJit-LLVM runtimelab branch.

#### Setup

1) Replace the occurences of `C:\Users\Accretion\source\dotnet` in `RyuJitReproduction/RyuJit.sln` with `$REPO_ROOT`.
2) Initialize and configure `runtime` and `runtime-base` repositories:
   - Clone `dotnet/runtime`.
   - Add two remotes: `origin` for the fork, `upstream` for the main repostory.
3) Install [PIN](https://www.intel.com/content/www/us/en/developer/articles/tool/pin-a-dynamic-binary-instrumentation-tool.html) into `diffs/pin` (the end result would be `diffs/pin/pin-3.19-98425-gd666b2bee-msvc-windows`). Create a new [PIN tool](https://gist.github.com/SingleAccretion/322071577c481040e409b98b6e936adf), named `SingleAccretionPinTool`, under `diffs/pin/pin-3.19-98425-gd666b2bee-msvc-windows/source/tools` and build it from the Windows command prompt, with the `C:\cygwin64` directory in `PATH`: `make obj-intel64/SingleAccretionPinTool.dll && make obj-ia32/SingleAccretionPinTool.dll TARGET=ia32`.
4) Pull and build the upstream:
   - Run `buid/regenerate-artifacts.ps1`. This will take a long time, as it builds `runtime` and `runtime-base` in 3 configurations for CoreCLR and one (Release) for libraries.
   - In parallel, run `diffs/redownload-spmi-collections.ps1`. This may take even longer and will consume approximately 75 GB of disk space.
   - The above two steps are intended to be repeated each time upstream needs to be synced to (the author does them about once a week).
5) TODO: document things required for working with the RyuJit-LLVM runtimelab branch.

### "Build" scripts

#### `build-jit-with-stats-defined.ps1` - build the Jits capable of measuring certain "stat"

This is mostly an infrastructural script, but can also be used directly. It allows building compilers with a number of `#define`s that control various interesting dumping capabilities.

Parameters:
1) `-base`: the Jits should be built out of `runtime-base`.
2) `-save`: whether the state of the source repository should be restored after the Jits have been built (otherwise `clrjit` artifacts will be overwritten). When this option is used, the built Jits will be placed under `build/[Base]CustomJits`.
3) `-jitSubset`: `clr.jit` or `clr.alljits`.
4) `-arch`: `x64` or `x86` (the host arch of the built compilers).
5) `-config`: the configuration (`Debug`/`Checked`/`Release`).
6) `-stats`: which "stats" to "define". See the script source for how they correspond to `#define`s in `jit.h`.

#### `regenerate-artifacts.ps1` - rebuild `runtime` and `runtime-base`

Also builds custom Jits with the ability to measure memory consumption (used by `diff-mem.ps1`).

Parameters:
1) `-arches`: the architectures to build, `x64` and `x86`.
2) `-save`: whether to purge the existing artifacts with `git clean -xdf`.
3) `-pull`: whether to pull the latest upstream before rebuilding (default when `-save` is off).
4) `-baseOnly`: whether to only rebuild `runtime-base`.

#### `save-base-jits.ps1` - "save" the currently built Jits

A number of scripts support overriding the "base" Jit (which is usually the one built out of `runtime-base`) with a custom one, placed under `diffs/base-jits-[x64|x86]` by this script.

Parameters:
1) `-hostArch`: the architecture of the Jits to copy. Default is `x64`.
2) `-config`: the configuration of the Jits to copy. Default is `Checked`.
3) `-builtJitsPath`: the path to the Jits to copy. By default, the script copies the Jit from `runtime`'s artifacts.

#### `update-custom-core-root.ps1` - update the custom core roots

Copies artifacts from the built repositories to "custom" core root repositories. "Custom" core roots differ slightly in their construction from the ones created by the test build script, in particular, they are set up such that the runtime copied is `Checked`, while the Jits are `Debug`, for ease of debugging, and the `crossgen2` pseudo-custom core root employs a renaming trick so that the Jit compiling CG2 in its process has a name different than the one used by CG2 itself.

Parameters:
1) `-arch`: the architecure of the core root. Default is `x64`.
2) `-cg2`: whether to update the CG2 core root. Off by default.
3) `-ilc`: whether to update the ILC core root. Note this refers to the RyuJit-LLVM runtimelab branch. Off by default.
4) `-mono`: whether to update tehe Mono core root (CoreCLR core root with the runtime binaries replaced with their Mono equivalents). Off by default.

#### `update-jit.ps1` - "update" the Jit in the custom core root

Builds and copies the Jits from `runtime`'s artifacts to their location in the custom core root(s). This is the workhorse script in the workflow, it is expected to be used alongside editing the source code, to test the resulting binaries.

Parameters:
1) `-hostArch`: the architercture of the Jits to build. Default is `x64`.
2) `-all`: whether the build "all" of the Jits (i. e. `clr.alljits`). By default, only the subset `clr.jit` is built.
3) `-release|-r`: whether to build the Jits in `Release` configuration. By default, `Checked` and `Debug` Jits are built.
4) `-refreshPdb|-p`: whether to regenerate the PDB files from scratch during the build. By default, the incremental build "appends" debugging information to the existing files, which can cause confusion in certain scenarios.
5) `-updateBaseJits|-b`: whether to make the built Jits "base" (copy them the "base Jits" directory with `save-base-jits.ps1`). This is a very useful option when the "base" being diffed against (say, via SPMI) is not the same as the `HEAD` of `runtime-base` (which is intended to always be in sync with the `HEAD` of the remote fork and only update infrequently). In such a case, the common sequence of actions to perform is the following
   - `git rebase main -i` and `break` after the intended "base" commit.
   - `update-jit -b [-all]`
   - `git rebase --continue`
   - `update-jit [-all]`
   - Run `diff-mem`, `pin`, `spmi`, etc.
6) `-llvmRyuJit`: whether to build and update the Jit associated with the RyuJit-LLVM runtimelab branch.
7) `-cg2`: whether to update the CG2 custom core root. Note this is off by default.
8) `-pgo`: whether to apply native PGO to the built Jits. By default, `Release` Jits are built with PGO off, to make PIN diffs reliable.
9) `-stats`: the list of "stats" to build the Jits with. See the above notes on `build-jit-with-stats-defined.ps1`.

### "Diff" scripts

#### `diff-dasm.ps1` - view the diffs between SPMI-generated assembly and/or JitDump files

This is the primary script for working with SPMI-generated diffs. It is intended to be invoked in the directory created by `superpmi.py` (e. g. `C:\Users\Accretion\source\dotnet\diffs\spmi\asm.libraries.pmi.windows.x64.checked.44`). Note that most of the parameters to the script can be shortened per the standard PowerShell rules (e. g. `-log` => `-l`, `-wordDiff` => `-w`, `-basediffs` => `-b`, etc).

Parameters:
1) `-spmiIndex` (positional): the SPMI index for the diff of interest. This is the only required parameter, and in absense of any others, it makes the script equivalent to invoking `git diff --no-index base/spmiIndex.dasm diff/spmiIndex.dasm`.
2) `-perfScore`: a shortcut for `jit-analyze -b base -d diff -metric PerfScore`.
3) `-log`: whether to re-invoke SPMI on the provided diff and generate dump files for the base and diff, to be `git diff`ed. Note the script supports invocations without `-spmiIndex` in case `-log` was specificed, making it equivalent to `git diff --no-index baselog.cs log.cs`. This is useful when analyzing large dumps, where regenerating them is relatively expensive.
4) `-native`: whether to use "native" cross-compilers when invoking SPMI. By default, the script will prefer `x86`-hosted compilers for all `x86` and `ARM` diffs.
5) `-basediffs`: whether to use the "base Jit" with SPMI.
6) `-asm`: whether to re-invoke SPMI on the provided diff and generate `.dasm` files for the base and diff. Useful for verifying changes have the intended impact on the diff (note, as with `-log`, that the script creates the new `.dasm` files in the current directory, and does not overwite the originals).
7) `-wordDiff`: whether to use `--word-diff` in `git diff` invocations. Useful for diffing dump files, where changes to tree IDs can make ordinary `git diff` too noisy.
8) `-options`: an array of Jit options to provide to compilers invoked by SPMI. For example: `-o JitNoCSE=1, JitNoInline=1`. Exceptionally useful for verifying causes of diffs in conjuction with various `No` knobs.


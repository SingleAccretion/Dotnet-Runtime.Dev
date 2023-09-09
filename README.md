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
3) Install [PIN](https://www.intel.com/content/www/us/en/developer/articles/tool/pin-a-dynamic-binary-instrumentation-tool.html) into `diffs/pin` (the end result would be `diffs/pin/pin-3.19-98425-gd666b2bee-msvc-windows`). Create a new [PIN tool](https://gist.github.com/SingleAccretion/322071577c481040e409b98b6e936adf), named `SingleAccretionPinTool`, under `diffs/pin/pin-3.19-98425-gd666b2bee-msvc-windows/source/tools` and build it using "Native Tools Command Prompt", with the `C:\cygwin64\bin` directory in `PATH`: `make obj-intel64/SingleAccretionPinTool.dll` (using the x64 prompt), `make obj-ia32/SingleAccretionPinTool.dll TARGET=ia32` (using the x86 prompt).
4) Pull and build the upstream:
   - Run `buid/regenerate-artifacts.ps1`. This will take a long time, as it builds `runtime` and `runtime-base` in 3 configurations for CoreCLR and one (Release) for libraries.
   - In parallel, run `diffs/redownload-spmi-collections.ps1`. This may take even longer and will consume approximately 75 GB of disk space.
   - The above two steps are intended to be repeated each time upstream needs to be synced to (the author does them about once a week).
5) TODO: document things required for working with the RyuJit-LLVM runtimelab branch.

### "Build" scripts

#### `build-jit-with-stats-defined.ps1` - build the Jits capable of measuring a certain "stat"

This is mostly an infrastructural script, but can also be used directly. It allows building compilers with a number of `#define`s that control various interesting dumping capabilities.

Parameters:
1) `-base`: the Jits should be built out of `runtime-base`.
2) `-save`: whether the state of the source repository should be restored after the Jits have been built (otherwise `clrjit` artifacts will be overwritten). When this option is used, the built Jits will be placed under `build/[Base]CustomJits`.
3) `-jitSubset`: `clr.jit` or `clr.alljits`.
4) `-arch`: the host architecture of the built compilers, `x64` or `x86`.
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

A number of scripts support overriding the base Jit (which is usually the one built out of `runtime-base`) with a custom one, placed under `diffs/base-jits-[x64|x86]` by this script.

Parameters:
1) `-hostArch`: the architecture of the Jits to copy. Default is `x64`.
2) `-config`: the configuration of the Jits to copy. Default is `Checked`.
3) `-builtJitsPath`: path to the Jits to copy. By default, the script copies the Jits from `runtime`'s artifacts.

#### `update-custom-core-root.ps1` - update the custom core roots

Copies artifacts from the built repositories to "custom" core roots. These differ slightly in their construction from the ones created by the test build script, in particular, they are set up such that the runtime copied is `Checked`, while the Jits are `Debug`, for ease of debugging, and the `crossgen2` custom core root employs a renaming trick so that the Jit compiling CG2 in its process has a name different than the one used by CG2 itself.

Parameters:
1) `-arch`: the architecure of the core root. Default is `x64`.
2) `-cg2`: whether to update the CG2 core root. Off by default.
3) `-ilc`: whether to update the ILC core root. Off by default.
3) `-llvmIlc`: whether to update the ILC core root for the RyuJit-LLVM runtimelab branch. Off by default.
4) `-mono`: whether to update the Mono core root (CoreCLR core root with the runtime binaries replaced with their Mono equivalents). Off by default.

#### `update-jit.ps1` - update the Jits in custom core roots

Builds and copies the Jits from `runtime`'s artifacts to their location in the custom core root(s). This is the workhorse script in the workflow, it is expected to be used alongside editing the source code, to test the resulting binaries.

Parameters:
1) `-hostArch|-a`: the architercture of the Jits to build. Default is `x64`.
2) `-all`: whether to build "all" of the Jits (i. e. `clr.alljits`). By default, only the `clr.jit` subset is built.
3) `-release|-r`: whether to build the Jits in `Release` configuration. By default, `Checked` and `Debug` Jits are built.
4) `-refreshPdb|-p`: whether to regenerate the PDB files from scratch during the build. By default, the incremental build "appends" debugging information to the existing files, which can cause confusion in certain scenarios.
5) `-updateBaseJits|-b`: whether to make the built Jits "base" (copy them to the "base Jits" directory with `save-base-jits.ps1`). This is a very useful option when the "base" being diffed against (say, via SPMI) is not the same as the `HEAD` of `runtime-base` (which is intended to always be in sync with the `HEAD` of the remote fork and only infrequently updated). In such a case, the common sequence of actions to perform is the following:
   - `git rebase main -i` and `break` after the intended "base" commit.
   - `update-jit -b [-all]`
   - `git rebase --continue`
   - `update-jit [-all]`
   - Run `diff-mem.ps1`, `pin.ps1`, `spmi.ps1`, etc.
6) `-llvmRyuJit`: whether to build and update the Jit associated with the RyuJit-LLVM runtimelab branch.
7) `-pgo`: whether to apply native PGO to the built Jits. By default, `Release` Jits are built with PGO off, to make PIN diffs reliable.
9) `-configs`: list of configurations to build the Jits in. Useful to override the defaults.
9) `-stats`: the list of "stats" to build the Jits with. See the description of `build-jit-with-stats-defined.ps1`.

### "Diff" scripts

#### `diff-dasm.ps1` - view the diffs between SPMI-generated assembly and/or JitDump files

This is the primary script for working with SPMI-generated diffs. It is intended to be invoked in the directory created by `superpmi.py` (e. g. `C:\Users\Accretion\source\dotnet\diffs\spmi\asm.libraries.pmi.windows.x64.checked.44`). Note that most of the parameters to the script can be shortened per the standard PowerShell rules (e. g. `-log` => `-l`, `-wordDiff` => `-w`, `-basediffs` => `-b`, etc).

Parameters:
1) `-spmiIndex` (positional): the SPMI context index. This is the only required parameter, and in absense of any others, it makes the script equivalent to invoking `git diff --no-index base/spmiIndex.dasm diff/spmiIndex.dasm`.
2) `-perfScore`: a shortcut for `jit-analyze -b base -d diff -metric PerfScore`.
3) `-log`: whether to re-invoke SPMI on the provided diff and generate dump files, to be `git diff`ed. Note that the script supports invocations without `-spmiIndex` in case `-log` was specificed, making it equivalent to `git diff --no-index baselog.cs log.cs`. This is useful when analyzing large dumps, where regenerating them is relatively expensive.
4) `-native`: whether to use "native" cross-compilers when invoking SPMI. By default, the script will prefer `x86`-hosted compilers for all `x86` and `ARM` diffs.
5) `-basediffs`: whether to use the "base" Jit with SPMI.
6) `-asm`: whether to re-invoke SPMI on the provided diff and generate `.dasm` files. Useful for verifying changes have the intended impact on the diff (note, as with `-log`, that the script creates the new `.dasm` files in the current directory, and does not overwite the originals).
7) `-wordDiff`: whether to use `--word-diff` in `git diff` invocations. Useful for diffing dump files, where changes to tree IDs can make ordinary `git diff` too noisy.
8) `-options`: an array of Jit options to provide to compilers invoked by SPMI. For example: `-o JitNoCSE=1, JitNoInline=1`. Exceptionally useful for verifying causes of diffs in conjuction with various `JitNo` knobs.

#### `diff-mem.ps1` - diff the memory consumption

As the name suggests, the script is intended for quick and simple verification of changes that could impact memory consumption of the Jit. Currently, it only supports diffs with CoreLib compiled via CG2. This script relies on base Jits capable of measuring memory stats being present under the `build` directory.

Parameters:
1) RID and host arch (positional): what host/target combination should be used for the diffs. The "RID" is a standard .NET RID (e. g. `win-x64`, `linux-arm`, etc), while the host arch can be one of `x86` or `x64`. Default is `win-x64 x64`.
2) `basediffs (positional): whether to use the "base" Jit for the diff.

#### `fmt.ps1` - apply the Jit formatting patch

This script downloads and applies the formatting patch generated by the AzDo jobs that run on Jit changes.

Parameters:
1) `-download` (positional): the build ID for the formatting job. It is intended to be extracted from the URL, e. g.: https://dev.azure.com/dnceng/public/_build/results?__buildId=1927902__&view=logs&jobId=c8204876-824e-5bf9-8c45-a4628bfcec7d.
2) `-linux`: whether to use the Linux job's artifacts to obtain the formatting patch. By default, Windows' ones are used.

#### `mcs.ps1` - wrapper over the `mcs.exe` native tool

Simply passes through the provided arguments to the underlying tool, taken from `runtime`'s artifacts.

#### `pin.ps1` - diff the TP impact, measured as the count of retired instructions

This script uses the PIN tool built earlier to make estimating the TP impact of a given change very simple and quick. It protects against the common mistake of not accounting for missing contexts, as well as allowing for diffs in cases where they can be filtered out.

Parameters:
1) RID and host arch (positional): what host/target combination should be used for the diffs. The default is `win-x64 x64`.
2) Path to the `.mch` file to diff (positional): explicit path to the `.mch` file to use for diffs.
3) Name of the collection to use for diffs, one of `aspnet`, `bench`, `clrtests`, `cglibs`, `libs` or `libstests`. By default, the `bench` collection is used.
4) Comma-separated list of contexts, in the same format as that of `superpmi.exe`, e. g. `1-100,90-9000`: the contexts to use for diffs. Diffing whole collections takes a considerable amount of time, so this option can be quite handy for quick estimates.
5) Jit options, in the format of `JitOption=Value`: options to use for both "base" and "diff" Jits when running them.
6) `basediffs`: whether to use the "base" Jit for the diff.
7) Path to a `.dll` file: the PIN tool library to use for the diffs. Useful for testing in-development PIN tools.
8) `trace`: whether to use the "trace" mode of the PIN tool. Traces will be saved to `diffs/basetp.txt` and `diffs/difftp.txt` and analyzed with `analyze-pin-trace-diff.ps1`.
9) `tracediff`: same as `trace`, but only instrument the "diff" Jit and use results from `diffs/basetp.txt` as the base.

#### `analyze-pin-trace-diff.ps1` - diff the traces produced by the PIN tool

Analyzes the information obtained with the PIN tool's `trace` option:
```
Base: 1039322782, Diff: 1040078986, +0.0728%

`Compiler::optCopyPropPushDef'::`2'::<lambda_1>::operator()      : 1073512 : NA       : 18.17% : +0.1033%
SsaBuilder::RenamePushDef                                        : 911022  : NA       : 15.42% : +0.0877%
`Compiler::fgValueNumberLocalStore'::`2'::<lambda_1>::operator() : 584435  : NA       : 9.89%  : +0.0562%
Compiler::lvaLclExactSize                                        : 244692  : +60.09%  : 4.14%  : +0.0235%
ValueNumStore::VNForMapSelectWork                                : 87006   : +2.78%   : 1.47%  : +0.0084%
GenTree::DefinesLocal                                            : 82633   : +1.63%   : 1.40%  : +0.0080%
Rationalizer::DoPhase                                            : -91104  : -6.36%   : 1.54%  : -0.0088%
Compiler::gtCallGetDefinedRetBufLclAddr                          : -115926 : -98.78%  : 1.96%  : -0.0112%
Compiler::optBlockCopyProp                                       : -272450 : -5.75%   : 4.61%  : -0.0262%
Compiler::fgValueNumberLocalStore                                : -313540 : -50.82%  : 5.31%  : -0.0302%
Compiler::GetSsaNumForLocalVarDef                                : -322826 : -100.00% : 5.46%  : -0.0311%
SsaBuilder::RenameDef                                            : -478441 : -28.33%  : 8.10%  : -0.0460%
Compiler::optCopyPropPushDef                                     : -711380 : -55.34%  : 12.04% : -0.0684%
```
The columns, in order:
1) The instruction count difference for the given function.
2) Same as `1`, but relative. May be `NA`, indicating the base didn't contain the given function, or `-100%` indicating the diff didn't.
3) Relative contribution to the diff. Calculated as `abs(instruction diff count) / sum-over-all-functions(abs(instruction diff count))`.
4) Relative difference, calculated as `instruction diff count / total base instruction count`.

Parameters:
1) `-baseTracePath`: path to the base trace file.
2) `-diffTracePath`: path to the diff trace file.
3) `-noiseFilter`: filter out function with contributions lower than this number (specified as a percentage). `0.1%` by default.
4) `-functionsFilter`: filter out functions with these names. All functions are shown by default.

#### `redownload-spmi-collections.ps1` - download a set of commonly useful collections

Downloads SPMI collections for the `win-x64`, `win-x86`, `win-arm64`, `linux-arm` and `linux-x64` targets. This is a wrapper over `spmi.ps1`'s `redownload` functionality.

#### `sbcg-reducer.ps1` - help find the method with silent bad codegen

Performs binary search through method hashes to identify which method, when not run under MinOpts, leads to the test case failing. Relies on a custom `JitMinOptsRange` Jit config toggle.

Parameters:
1) `-command`: the command to run as the test case.
2) `-toggle`: the environment variable to use as the range, specified via a hexadecimal pair of numbers, inside which all methods will be compilerd without optimizations.
3) `-successExitCode`: the exit code of `command` which indicates "success". The default is `100`, same as for CoreCLR tests, though note that test wrapper scripts actually use `0` as the "success" value.
4) `-quiet`: suppress console output of the test case.

#### `send-diffs.ps1` - commit diffs to a dedicated repository

Under `diffs`, there is a `diffs-repository` directory, which is inteded to be used in conjuction with this script to store diffs in a `git`-based database. While SPMI in CI has mostly eliminated the need for this, it is still occasionally useful, especially when the volume of diffs is too large for CI to handle.

Before using this, `diffs-repository` must be initialized as a valid `git` repository and connected to some default remote.

Parameters:
1) `-prIndex`: number of the pull request for which the diffs are being commited.
2) `-mdIndex`: index of the `.md` summary file to commit. This is as generated by `superpmi.py`, e. g. for `C:\Users\Accretion\source\dotnet\diffs\spmi\diff_summary.173.md` it would be `173`.
3) `-repositoryName`: name of the repository for which the diffs are being commited. Default is `runtime`.
4) `-showDiffs|-d`: whether to "show" the diffs (via `git show`) before committing them.

#### `set-test-env.ps1` - set environment variables before running CoreCLR tests

Very useful for quickly getting a new terminal instance configured for running CoreCLR tests, as well as switching between different core roots and stress configurations.

Parameters:
1) `-arch`: architecture of the core root to use. Default is `x64`.
2) `-nativeAot`: whether the test environment is to be set up for NativeAOT-LLVM testing. Sets `CLRCustomTestLauncher`.
3) `-tieredCompilation`: whether to enable tiered compilation. By default, it is turned off.
4) `-base`: whether to use the core root from the `runtime-base` repository. By default the "custom" core roots are used.
5) `-stressLevel`: the level to use for `JitStress`, if any. By default, no stress is applied.

#### `spmi.ps1` - wrapper over `superpmi.py`

Ordinarily, invoking `superpmy.py`, especially in cross-targeting and filtering scenarios, can be quite verbose. This script is meant to optimize that friction away. Additioanlly, it provides retry loop support for downloading collections, where one can kill the python process and have it start over, which can be useful in cases (such as accidentally putting the computer to sleep), where the download process "freezes".

Note the somewhat inordinate way in which the script takes arguments: they are all positional, and must be in strict order (defined below), except if the effective values used are the same as default ones. This means that, e. g., both `spmi win-x64 bench` and `spmi bench` are legal, but `spmi bench win-x64` is not.

Parameters:
1) Action: one of `replay`, `asmdiffs`, `basediffs`, `perfdiffs` (PerfScore diffs), `perfbasediffs` and `redownload`. `basediffs` and `perfbasediffs` are the same as `asmdiffs` and `perfdiffs`, respectively, except that they use the "base" Jits. The default is `asmdiffs`.
2) Target RID and host arch: the defaults are `win-x64` and `x64`. Like `diff-mem.ps1` and `diff-dasm.ps1`, `spmi.ps1` will prefer to use the `x86`-hosted compilers for `x86` and `ARM` diffs.
3) Collection: one of `aspnet`, `bench`, `clrtests`, `cglibs`, `libs` or `libstests`. While replay and asmdiffs only support specifiying one collection, or none, in which case all are used, the `redownload` action supports a whitespace-separated list of them.
4) Jit options: `b:JitOption=Value` if the option should apply only the the base compiler, `d:JitOption=Value` for the opposite, and simply `JitOption=Value` if it should apply to both.

#### `unpack-dasm.ps1` - download and unpack diffs produced by SPMI in CI

This simple script helps in quickly pulling down CI-produced diffs for local analysis.

Parameters:
1) `-download`: the build ID to use when downloading the diffs (as with `fmt.ps1`, this can be obtained from the AzDo URL).
2) `-zipFile`: the path to an existing ZIP file to unpack. This option is meant to be used when the diffs file has already been downloaded.
3) `-arch`: the host architecture of the SPMI job, `x86` or `x64`. Default is `x64`.

#### `touch.ps1` - update the timestamp on a file

This script works similarly to the "touch" Unix utility, except it does not create the file if it does not exit. This script is useful for working around MSBuild incrementality limitations: "touch" the project file before invoking `dotnet build` to have it be fully rebuilt.

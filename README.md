# pocketbook-boilerplate

Minimal, modern starting point for native **PocketBook InkView** apps (C, CMake),
with a one-command build → deploy → launch loop against
[pbemu](https://codeberg.org/datyoma/pbemu).

- **Toolchain:** Debian's stock `arm-linux-gnueabi(hf)` GCC 12 in a container.
  No 2014-era i386 `arm-obreey` toolchain is needed.
- **Libraries:** links directly against the `libinkview.so` from *your* staged
  firmware, so the ABI matches the device exactly. Soft/hard-float is
  auto-detected from the firmware libc.
- **Headers:** official `inkview.h` & friends from
  [pocketbook/SDK_6.3.0](https://github.com/pocketbook/SDK_6.3.0) (branch `6.5`, pinned),
  fetched by `./pb setup` (not committed).

## Quick start

### Prerequisites
- Podman OR Docker
- Make sure to setup and run the pbemu repo first with the chosen firmware:
https://codeberg.org/datyoma/pbemu

- Make sure the repo is checked out at location: ../pbemu

### Running the PocketBook application

```sh
# once: build the toolchain image and fetch the SDK headers
./pb setup

# with the emulator running (../pbemu/pbemu start):
./pb run        # build + copy to /mnt/ext1/applications + launch in foreground
./pb log        # follow app stdout/stderr (it goes to monitor.log)
```

The firmware is auto-detected as the single staged dir in `../pbemu`
(e.g. `U710_6.11.2124`). Override it with `PB_FIRMWARE=/path/to/staged_fw` or
`PBEMU_DIR=...`.

| Command | What it does |
|---|---|
| `./pb setup` | build the `pocketbook-sdk` image, fetch headers into `sdk/include` |
| `./pb build [--debug]` | cross-compile into `build/` (Release, stripped, by default) |
| `./pb deploy` | copy the app into the emulator's `/mnt/ext1/applications` |
| `./pb run` | build + deploy + (re)start the app and bring it to the foreground |
| `./pb log` | tail the emulator's `monitor.log` |
| `./pb install <mount>` | copy to a real device mounted over USB (`<mount>/applications/`) |
| `./pb shell` | shell inside the toolchain container |
| `./pb clean` | remove `build/` |

## On a real device

```sh
./pb build
./pb install /run/media/$USER/PocketBook   # wherever the device is mounted
```

Eject the device. The app then appears under **Applications**.

## Layout

```
CMakeLists.txt                  app target (+ pb-launch helper)
cmake/pocketbook-toolchain.cmake cross toolchain: compiler, flags, firmware libs
Containerfile                   Debian bookworm + ARM cross GCC + zlib headers
src/main.c                      the hello world app
tools/pb-launch.c               launches an app as a task + SetActiveTask()
pb                              host-side helper script
sdk/include/                    (generated) InkView SDK headers
build/                          (generated) build output
```

To start your own app, rename `hello_world.app` in `CMakeLists.txt` and the
`APP=` line in `pb`, then add sources to `add_executable`.

## InkView in 30 seconds

An InkView app hands control to `InkViewMain(handler)`. The firmware then calls
your handler with events:

| Event | When |
|---|---|
| `EVT_INIT` | once at startup (open fonts, load state) |
| `EVT_SHOW` | the app becomes visible, so redraw everything |
| `EVT_POINTERDOWN/UP/MOVE` | touch, with `par1`/`par2` = x/y |
| `EVT_KEYPRESS` | hardware keys (`IV_KEY_BACK`, `IV_KEY_PREV`, `IV_KEY_NEXT`, ...) |
| `EVT_EXIT` | shutting down (free resources) |

Drawing goes to an off-screen canvas (`ClearScreen`, `DrawTextRect`, `FillArea`,
`DrawBitmap`, ...). Nothing appears until you push it to the e-ink panel:
use `FullUpdate()` for a full flashing refresh, `SoftUpdate()`, or
`PartialUpdate(x, y, w, h)` for fast local changes. See `sdk/include/inkview.h`
for the full API. It is well commented.

## Notes / gotchas

- Binaries built here need only `GLIBC_2.34` or older. 6.x firmware ships
  glibc 2.4x, so they run without bundling a libc.
- On 6.x firmware `NewTaskEx()` hands the launch to `monitor.app` and returns
  `0`, and the new task stays in the background. `tools/pb-launch.c` looks the
  task up and calls `SetActiveTask()`. pbemu's own `arm_probe launch` doesn't
  do this, so a launched app appears to hang.
- The old `kotborealis/pocketbook-sdk-sample` + `SDK_481` approach fails on
  modern hosts with an `as: loadlocale.c ... Assertion` crash. Its 32-bit
  assembler chokes on the host locale (`LC_ALL=C` works around it). The
  toolchain is also GCC 4.8.

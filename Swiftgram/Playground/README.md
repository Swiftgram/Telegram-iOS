# Swiftgram Playground

Small app to quickly iterate on components testing without building an entire messenger.

## (Optional) Setup Codesigning

Create simple `codesigning/Playground.mobileprovision`. It is only required for non-simulator builds and can be skipped with `--disableProvisioningProfiles`.

## Generate Xcode project

Same as main project described in [../../Readme.md](../../Readme.md), but with `--target="Swiftgram/Playground"` parameter.

## Run generated project on simulator

### From root

```shell
./Swiftgram/Playground/launch_on_simulator.py
```

### From current directory

```shell
./launch_on_simulator.py
```

# fix-signal-oneplus13

Fix signal and bootloop for OnePlus 13 CN on OxygenOS 15 / 16.

[Download](https://github.com/K58/fix-signal-oneplus13/releases)

> [!WARNING]
> **PSA: Anti-Rollback Protection**
>
> OnePlus has implemented anti-rollback protection starting with firmware version **16.0.3.50x**.
>
> If you are on **16.0.3.50x or higher**, **DO NOT downgrade** to any earlier version:
> * This will cause a **HARD BRICK**.
> * **Leaked EDL tools will not work.** Anti-rollback is specifically designed to block them.
> * Only official/authorized EDL access can fix this state.
>
> Please be careful when flashing any ROMs.
>
> ~~Never Settle.~~ **Sometimes Settle.**

## Tutorial

### How to fix signal

Download and install this module in Magisk (or other root manager).

### Network access with temporary root

Some temporary-root sessions can register on the mobile network while SELinux
blocks network packets and IMS registration. This module includes `sepolicy.rule`
to allow the required packet, interface, node and peer permissions while keeping
SELinux enforcing. Outbound grants are limited to domains already assigned network
access (`netdomain`) and kernel network processing; inbound grants use the default
`unlabeled`, `netif` and `node` labels observed in the denial logs.

On the tested OnePlus 13 CN running OxygenOS 16.0.7.201 with ReSukiSU v4.2.0-rc3,
these rules restored HTTPS access and IMS registration; a phone call was also
confirmed working. The SU manager must load the module's policy after root is
obtained. A full reboot clears temporary root and the live policy changes.

The NV image mapping must also be active when the modem reads its configuration.
This fork adds `late-load.sh` and a `service.sh` fallback. After boot finishes,
the recovery worker applies the network policy and SAR property, creates or
reuses the NV loop device, and checks the device actually opened by `rmt_storage`.
If it still uses the original image, or the radio remains off, the worker restarts
`rmt_storage`, verifies it opened the replacement, then reinitializes the modem.
If storage already uses the replacement and the radio is on, it skips the restart.

Automatic recovery supports project **23821**, Android **16**, and the detected
`4080000.remoteproc-mss` modem. It waits up to two minutes for boot completion,
defers recovery in airplane mode or without a ready SIM, and waits up to one
minute for calls to end. Missing call-state information also prevents a restart.
Concurrent hooks share a lock. Automatic disruptive recovery is attempted at most
once per kernel boot; a failed or deferred recovery can be retried using Action.
The modem is started again on a handled interruption if it was left offline.
Network registration and actual service availability can still take time after
the restart; inspect the log and test mobile data and a normal phone call.

For a temporary-root setup, regain root after each full reboot or OTA and let
the module load again. The inactive-slot boot-image root installation described
below applies to persistent root with an unlocked bootloader.

On **Android 16**, the module's **Action** button runs a guarded manual retry.
On **Android 15**, Action retains the original OTA `dtbo` patch flow described
below. The automatic Android 16 recovery only changes runtime mappings, policy
and modem state; the original physical NV image is not flashed.

Diagnostics (root shell):

```sh
sh /data/adb/modules/fix-signal-oneplus13/recover-radio.sh --check
cat /data/adb/modules/fix-signal-oneplus13/radio-recovery.log
```

`--check` is read-only. Recovery appends to `radio-recovery.log`; early mapping
appends to `post-fs-data.log`. Disabling/removing the module prevents subsequent
recovery. A full reboot clears live mappings and policy changes; temporary root
must be obtained again. Restore the original module version to remove this fork's
automatic recovery. Upstream automatic updates are disabled for this fork.

Build the installable ZIP with `powershell -File .\build.ps1`. It is written to
`dist/fix-signal-oneplus13-v4.2-temp-root.zip` with Android text files normalized
to LF. Run the mocked safety checks with `sh tests/radio-recovery-test.sh`.

### How to fix bootloop

Make sure you have this module installed before OTA updates.

1. Finish an OTA system update, but DO NOT click Restart.

2. On **Android 15**, press the "Action" button under the module name to patch the pending OxygenOS 15 OTA, and make sure the patch is successful.
    - **OxygenOS 16** does not require this bootloop patch. Skip this step for an OxygenOS 16 OTA. In this fork, Action on Android 16 performs runtime radio recovery instead.

3. You MUST also install Magisk (or other root manager) to inactive slot.
    - For Magisk: Magisk Manager -> Home -> Magisk (Install) -> Install to Inactive Slot (After OTA)

4. Press "Restart" in System Update

> [!WARNING]  
> **This module will modify `dtbo` partition to fix bootloop.** <br>
> Do NOT lock the bootloader with modified `dtbo` (or any other partition) in **any** slot.

### How to relock bootloader

**Please don't.**

Your device will **brick** if you relock the bootloader with any modifications to the system partition in **any** slot (e.g., root, dtbo, custom kernel, etc.).

> [!CAUTION]
> **Boot-image root and the Android 15 OTA `dtbo` patch require an unlocked bootloader.** The Android 16 temporary-root recovery uses runtime changes. Keep the bootloader unlocked if any verified partition has been modified. <br>
> 
> To relock the bootloader, you **MUST** remove root and restore the device to stock state.<br>
> **Relocking the bootloader is a dangerous operation.** Do not relock your bootloader unless you fully understand what you are doing.<br>
> On OnePlus 13, you cannot access fastboot again via key combination if the bootloader is locked.<br>
> If you lock your bootloader while rooted or modified, your phone will hard brick and cannot be recovered by yourself.
>
> If **any** of the following are not met, relocking the bootloader **will brick your device**:
>
> * **Every system partition in BOTH slots must be 100% stock and unmodified.**
>   * To ensure this, after restoring the latest version of stock OS on your device, download the full OTA ROM (.zip) for that OS version and local install it TWICE: local install, then reboot, then local install it AGAIN.
>   * Be very careful when rolling back to an older OS version. If your device has upgraded to an OS version with anti-rollback, downgrading to any earlier version will brick it. **Please read [the warning](#fix-signal-oneplus13) above.**
> * **Google account must be removed.**
>   * On older ColorOS / OxygenOS versions, due to a critical bug, FRP (Factory Reset Protection, a.k.a. activation lock) prevents completing the initial setup, effectively bricking it.

----

## Thanks to

- [@koaaN](https://xdaforums.com/m/koaan.3433581/)

- [@docnok63](https://xdaforums.com/m/docnok63.4967345/)

- [rapperskull](https://github.com/rapperskull)






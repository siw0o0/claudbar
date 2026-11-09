# Wydma

A desktop widget for KDE Plasma 6: a column of cards in sand, sky and terracotta, made to sit on a desert wallpaper. The interface is in Polish.

- **Clock** and date.
- **Claude limits**: the 5-hour and weekly usage, read from the file the [Claudbar](../README.md) plugin writes (`~/.cache/claudbar/usage.json`).
- **CPU and GPU** load and temperature; **memory**, VRAM and disk; **network** speed with a graph.
- **Power**: battery, power profile, the headset's battery.
- **VPN** state, with a warning while Proton VPN's kill switch blocks the network.

It was built for one laptop (a Lenovo Legion with an NVIDIA card) and says so in places:

- The GPU is read from the system sensor `gpu/gpu2`. If yours has another id (System Monitor shows it), change `gpu` at the top of `plasmoid/contents/ui/main.qml`. An NVIDIA card is read only on AC power, because the reading keeps it awake.
- The battery is `BAT0` and the charger `ADP0`.

## Install

```bash
./install.sh
```

Then add **Wydma** to the desktop from *Add Widgets…*.

## Optional parts

Cards and switches that need a helper show up only when the helper is installed. The helpers are in `helpers/`; read them before installing, two of them run as root.

- **Charging mode** (`helpers/battery-mode`): switches the battery between conservation, standard and fast charging through `charge_types`. Install it as `/usr/local/sbin/battery-mode` and let your user run it without a password:

  ```
  # /etc/sudoers.d/91-battery-mode
  yourname ALL=(root) NOPASSWD: /usr/local/sbin/battery-mode
  ```

- **Graphics mode** (`helpers/gpu-mode`): Hybrid, iGPU or dGPU on Legion laptops with the `legion_laptop` driver, applied at the next boot. Install it as `/usr/local/sbin/gpu-mode` with a sudoers line like the one above.
- **VPN switch and list** (`helpers/protonvpn-auto`): keeps Proton VPN (its CLI) on everywhere except the networks listed in `NOVPN_SSIDS`, and switches to other VPN profiles from NetworkManager. Install it as `~/.local/bin/protonvpn-auto`; run it from a NetworkManager dispatcher script and at login to have it follow network changes.
- **Next classes**: an executable `~/.config/wydma/plan` that prints one line of JSON, `{ "pobrano": ISO time, "zajecia": [{ "przedmiot", "forma", "start", "koniec", "sala", "budynek", "uwaga" }] }` (`start` and `koniec` are ISO times). A click on the card runs `~/.config/wydma/plan-open`, if there is one.

## Uninstall

```bash
./install.sh remove
```

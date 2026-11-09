#!/bin/sh
# Jedna linia JSON dla widżetu: limity Claude, zasilanie, VPN, słuchawki.
# Wołany co 10 s, więc bez ciężkich narzędzi: profil zasilania z D-Bus, jedno wywołanie nmcli
# i jedno upower. Z argumentem "full" dochodzi lista profili VPN (zmienia się rzadko).

# Limity zapisuje mod Claudbar; starszy plik zostaje jako zapas.
usage=$(cat "$HOME/.cache/claudbar/usage.json" 2>/dev/null || cat "$HOME/.cache/claude-usage.json" 2>/dev/null)
[ -n "$usage" ] || usage=null

profile=$(busctl get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles \
  org.freedesktop.UPower.PowerProfiles ActiveProfile 2>/dev/null | sed -n 's/^s "\(.*\)"$/\1/p')
[ -n "$profile" ] || profile=$(powerprofilesctl get 2>/dev/null)

active=$(nmcli -t -f TYPE,NAME con show --active 2>/dev/null)
vpn=$(echo "$active" | awk -F: '$1=="wireguard"||$1=="vpn"{print $2; exit}')
# Kill switch Protona: interfejs pvpn-killswitch. Bez tunelu oznacza blokadę internetu.
ks=$(echo "$active" | grep -q '^dummy:pvpn-killswitch' && echo 1 || echo 0)
off=$( [ -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/protonvpn-manual-off" ] && echo 1 || echo 0)
# Profil Wi-Fi nosi nazwę sieci.
edu=$(echo "$active" | grep -qi '^802-11-wireless:eduroam$' && echo 1 || echo 0)

# Lista wyboru: profile VPN z NetworkManagera, bez profili tworzonych przez Protona.
vpns=null
if [ "$1" = full ]; then
  vpns="[$(nmcli -t -f NAME,TYPE con show 2>/dev/null | sed -n -E 's/:(vpn|wireguard)$//p' | grep -vE '^(ProtonVPN|pvpn)' | sed 's/\\:/:/g; s/\\/\\\\/g; s/"/\\"/g' | awk 'NR>1{printf ","}{printf "\"%s\"",$0}')]"
fi

bat=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo null)
ac=$(cat /sys/class/power_supply/ADP0/online 2>/dev/null || echo 0)
# Aktywny tryb ładowania jest w nawiasach: Fast [Standard] Long_Life.
charge=$(sed -n 's/.*\[\(.*\)\].*/\1/p' /sys/class/power_supply/BAT0/charge_types 2>/dev/null)

# Przełączniki pokazują się tylko tam, gdzie są ich skrypty (katalog helpers w repozytorium).
hascharge=$( [ -x /usr/local/sbin/battery-mode ] && [ -n "$charge" ] && echo 1 || echo 0)
hasgpu=$( [ -x /usr/local/sbin/gpu-mode ] && [ -d /sys/devices/platform/legion ] && echo 1 || echo 0)
hasvpn=$( [ -x "$HOME/.local/bin/protonvpn-auto" ] && echo 1 || echo 0)

# Tryb grafiki zapisany w firmware (legion_laptop) i faktycznie aktywny po starcie.
legion=/sys/devices/platform/legion
gpuset=""; gpunow=""; gpufail=""
if [ "$hasgpu" = 1 ]; then
  case "$(cat $legion/gsync 2>/dev/null):$(cat $legion/igpumode 2>/dev/null)" in
    0:*) gpuset=dgpu ;;
    1:1) gpuset=igpu ;;
    1:*) gpuset=hybrid ;;
  esac
  gpunow=igpu
  if [ -e /sys/bus/pci/devices/0000:01:00.0 ]; then
    gpunow=hybrid
    # Wewnętrzny ekran podłączony do NVIDII oznacza tryb dGPU.
    for c in /sys/class/drm/card*-eDP-*; do
      [ "$(cat "$c/status" 2>/dev/null)" = connected ] || continue
      card=${c##*/}; card=${card%%-*}
      [ "$(cat "/sys/class/drm/$card/device/vendor" 2>/dev/null)" = 0x10de ] && gpunow=dgpu
    done
  fi
  # Żądanie z tego startu czeka na restart, a z poprzedniego musi się już zgadzać z faktycznym trybem.
  if [ -r /var/lib/gpu-mode-target ]; then
    read -r target boot < /var/lib/gpu-mode-target
    if [ "$boot" = "$(cat /proc/sys/kernel/random/boot_id)" ]; then
      gpuset=$target
    elif [ "$target" != "$gpunow" ]; then
      gpufail=$target
    fi
  fi
fi

# Słuchawki: pierwsze urządzenie headset/headphones z jednego zrzutu upower.
headset=$(upower --dump 2>/dev/null | awk -F': *' '
  /^Device:/ { on = ($0 ~ /headset|headphones/) && !done }
  on && /model:/ { name = $2 }
  on && /percentage:/ { gsub("%", "", $2); pct = int($2); done = 1; on = 0 }
  END { if (done) { gsub(/["\\]/, "", name); printf "\"%s\" %d", name, pct } }')
hname=${headset% *}; hpct=${headset##* }
[ -n "$headset" ] || { hname='""'; hpct=null; }

printf '{"usage":%s,"profile":"%s","vpn":"%s","vpns":%s,"ks":%s,"manualOff":%s,"eduroam":%s,"bat":%s,"ac":%s,"charge":"%s","hasCharge":%s,"hasGpu":%s,"hasVpn":%s,"gpuSet":"%s","gpuNow":"%s","gpuFail":"%s","headset":%s,"headsetPct":%s,"now":%s}\n' \
  "$usage" "$profile" "$vpn" "$vpns" "$ks" "$off" "$edu" "$bat" "$ac" "$charge" "$hascharge" "$hasgpu" "$hasvpn" "$gpuset" "$gpunow" "$gpufail" "$hname" "$hpct" "$(date +%s%3N)"

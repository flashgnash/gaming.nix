# Mod Organizer 2 for any Steam game.
#
# MO2 has no native Linux build and its USVFS mod isolation only works when
# the game is started BY MO2 inside the game's own Proton prefix and Steam
# Linux Runtime container. The existing helpers all fall short of "any game"
# (NaK is archived, steamtinkerlaunch is pinned to MO2 2.4.4, MO2-LINT only
# supports a curated 23-game list), but the underlying mechanism is generic:
# a portable MO2 instance per game, launched with protontricks-launch so it
# lives in exactly the prefix + container the game itself uses.
#
# MO2 itself also only *manages* games it has a game plugin for (Bethesda
# titles natively, plus the bundled community "basic games" set). For
# anything else we auto-generate a minimal basic-game plugin into the
# instance (mods deploy over the game root; edit the generated
# plugins/basic_games/games/game_steam_<appid>.py to refine).
#
# Usage:
#   mo2               list Steam games (appid + name)
#   mo2 <name|appid>  launch MO2 for that game (creates the portable
#                     instance under ~/Games/mo2/<appid> on first run;
#                     pick "Portable" in MO2's first-run wizard)
#   mo2 %command%     as a Steam launch option — pressing Play launches MO2
#                     in the game's exact Proton/runtime invocation; start
#                     the game from inside MO2
#   mo2 nxm <url>     internal — nxm:// handler target; forwards Nexus
#                     "Mod Manager Download" links to the last-launched
#                     instance (MO2 single-instance forwards to a running one)
{ pkgs, ... }:
let
  mo2-dist = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "mod-organizer-2";
    version = "2.5.2";

    src = pkgs.fetchurl {
      url = "https://github.com/ModOrganizer2/modorganizer/releases/download/v${version}/Mod.Organizer-${version}.7z";
      sha256 = "05d8yj5i1i83mb2w1hm6dr9glyh6ixg40ng9msaxspgxhzynwdz6";
    };

    nativeBuildInputs = [ pkgs.p7zip ];

    unpackPhase = ''
      7z x "$src" -oextracted
    '';

    installPhase = ''
      mkdir -p "$out"
      cp -r extracted/. "$out"/
    '';
  };

  mo2 = pkgs.writeShellApplication {
    name = "mo2";

    runtimeInputs = with pkgs; [
      protontricks
      gnugrep
      findutils
    ];

    text = ''
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/mo2"
      instances_dir="$HOME/Games/mo2"
      creds_file="$state_dir/nexus-credentials.reg"
      settings_file="$state_dir/shared-settings.ini"
      mkdir -p "$state_dir"

      # Games MO2 supports via its native (DLL) game plugins — no stub needed.
      native_appids=" 22320 22300 22370 22380 22490 22330 72850 489830 611670 611660 377160 1716740 933480 976620 1151340 "

      steam_root=""
      for r in "$HOME/.local/share/Steam" "$HOME/.steam/steam"; do
        if [ -f "$r/steamapps/libraryfolders.vdf" ]; then
          steam_root="$r"
          break
        fi
      done
      if [ -z "$steam_root" ]; then
        echo "No Steam library found (looked for steamapps/libraryfolders.vdf)" >&2
        exit 1
      fi

      lib_paths() {
        grep -oP '"path"\s+"\K[^"]+' "$steam_root/steamapps/libraryfolders.vdf"
      }

      # appid<TAB>name for every installed game, across all library folders,
      # skipping Steam's own tooling apps (Proton, runtimes, redists).
      list_games() {
        lib_paths | while IFS= read -r lib; do
          for m in "$lib"/steamapps/appmanifest_*.acf; do
            [ -e "$m" ] || continue
            local id name
            id=$(grep -oPm1 '"appid"\s+"\K[^"]+' "$m" || true)
            name=$(grep -oPm1 '"name"\s+"\K[^"]+' "$m" || true)
            [ -n "$id" ] && [ -n "$name" ] || continue
            case "$name" in
              Proton* | "Steam Linux Runtime"* | Steamworks*) continue ;;
            esac
            printf '%s\t%s\n' "$id" "$name"
          done
        done
      }

      manifest_for() {
        lib_paths | while IFS= read -r lib; do
          if [ -e "$lib/steamapps/appmanifest_$1.acf" ]; then
            echo "$lib/steamapps/appmanifest_$1.acf"
            return
          fi
        done
      }

      game_dir_for() {
        local m installdir
        m=$(manifest_for "$1")
        [ -n "$m" ] || return 0
        installdir=$(grep -oPm1 '"installdir"\s+"\K[^"]+' "$m" || true)
        [ -n "$installdir" ] || return 0
        echo "$(dirname "$m")/common/$installdir"
      }

      game_name_for() {
        local m
        m=$(manifest_for "$1")
        [ -n "$m" ] || return 0
        grep -oPm1 '"name"\s+"\K[^"]+' "$m" || true
      }

      # Write a minimal basic-game plugin so MO2's instance wizard offers this
      # game, unless MO2 already supports it (native DLL or bundled basic_games
      # definition). $3 optionally names the game binary relative to game root.
      ensure_game_plugin() {
        local appid="$1" inst="$2" exe_rel="''${3:-}"
        local games_dir="$inst/plugins/basic_games/games"
        [ -d "$games_dir" ] || return 0
        case "$native_appids" in *" $appid "*) return 0 ;; esac
        grep -lw "$appid" "$games_dir"/*.py >/dev/null 2>&1 && return 0
        [ -e "$games_dir/game_steam_$appid.py" ] && return 0

        local name gamedir
        name=$(game_name_for "$appid")
        gamedir=$(game_dir_for "$appid")
        [ -n "$name" ] && [ -n "$gamedir" ] || return 0

        if [ -z "$exe_rel" ]; then
          # Shallowest plausible exe, biggest first on ties — skip helper junk.
          local exe
          exe=$(find "$gamedir" -maxdepth 3 -iname '*.exe' -printf '%d %s %p\n' 2>/dev/null \
            | grep -viE 'crashhandler|crashpad|crashreport|vcredist|dxsetup|dxwebsetup|easyanticheat|prereq|setup|install|redist|unins|dotnet' \
            | sort -k1,1n -k2,2nr | head -1 | cut -d' ' -f3-)
          [ -n "$exe" ] || return 0
          exe_rel="''${exe#"$gamedir/"}"
        fi

        local safe_name
        safe_name=''${name//'"'/}
        echo "Generating MO2 game plugin for '$name' ($appid, binary $exe_rel)"
        cat > "$games_dir/game_steam_$appid.py" <<EOF
      from ..basic_game import BasicGame


      class SteamGame$appid(BasicGame):
          Name = "$safe_name Support Plugin (auto-generated)"
          Author = "mo2-nix"
          Version = "1.0.0"

          GameName = "$safe_name"
          GameShortName = "steam$appid"
          GameSteamId = $appid
          GameBinary = "$exe_rel"
          # Mods deploy over the game root; change if this game has a
          # dedicated mods directory.
          GameDataPath = ""
      EOF
      }

      # ------------------------------------------------------------------
      # Shared global settings. MO2 keeps the Nexus login in the Windows
      # Credential Manager, which Wine persists per-prefix in user.reg under
      # HKCU\Software\Wine\Credential Manager (ARC4 blob + its per-prefix
      # EncryptionKey right next to it — portable if copied together). We
      # export that key after each session and import it into prefixes that
      # don't have a login yet. UI settings ([Settings] in ModOrganizer.ini)
      # are snapshotted the same way and seeded into fresh instances.
      # ------------------------------------------------------------------

      user_reg_for() {
        local m
        m=$(manifest_for "$1")
        [ -n "$m" ] || return 0
        echo "$(dirname "$m")/compatdata/$1/pfx/user.reg"
      }

      import_shared_creds() {
        local appid="$1" reg="$2"
        [ -s "$creds_file" ] || return 0
        [ -f "$reg" ] || return 0
        grep -q 'ModOrganizer2_' "$reg" && return 0
        if grep -q 'Credential Manager..Generic' "$reg"; then
          # Importing replaces the prefix's EncryptionKey, which would corrupt
          # credentials some other app stored here — leave it alone.
          echo "mo2: prefix already stores other credentials — not importing shared Nexus login" >&2
          return 0
        fi
        echo "Importing shared Nexus login into this game's prefix..."
        protontricks -c "wine regedit /S '$creds_file'" "$appid" >/dev/null 2>&1 || true
      }

      export_shared_creds() {
        local appid="$1" tmp="$state_dir/.creds-export-$$.reg"
        if protontricks -c "wine regedit /E '$tmp' 'HKEY_CURRENT_USER\Software\Wine\Credential Manager'" "$appid" >/dev/null 2>&1 \
          && [ -s "$tmp" ] && grep -q 'ModOrganizer2_' "$tmp"; then
          install -m 600 "$tmp" "$creds_file"
        fi
        rm -f "$tmp"
      }

      snapshot_settings() {
        local ini="$1/ModOrganizer.ini" tmp="$state_dir/.settings-$$.ini"
        [ -f "$ini" ] || return 0
        awk '/^\[Settings\]/{f=1} f && /^\[/ && !/^\[Settings\]/{exit} f' "$ini" > "$tmp"
        if [ -s "$tmp" ]; then
          mv "$tmp" "$settings_file"
        else
          rm -f "$tmp"
        fi
      }

      inject_settings() {
        local ini="$1/ModOrganizer.ini"
        [ -s "$settings_file" ] || return 0
        [ -f "$ini" ] || return 0
        grep -q '^\[Settings\]' "$ini" && return 0
        printf '\n' >> "$ini"
        cat "$settings_file" >> "$ini"
      }

      # Create the per-game portable MO2 instance if missing.
      # $2 = "vcrun" to also install the VC runtime (skipped when we're
      # already inside a Steam launch).
      ensure_instance() {
        local appid="$1" inst="$instances_dir/$1"
        if [ ! -e "$inst/ModOrganizer.exe" ]; then
          echo "Creating MO2 instance at $inst"
          mkdir -p "$inst"
          cp -r --no-preserve=mode,ownership ${mo2-dist}/. "$inst"/
          if [ "''${2:-}" = "vcrun" ]; then
            # MO2 wants the VC runtime; Proton prefixes don't always have it.
            # Non-fatal: newer Proton often copes without, and it can be re-run.
            echo "Installing vcrun2022 into the game prefix (one-off, may take a minute)..."
            protontricks "$appid" -q vcrun2022 \
              || echo "vcrun2022 install failed — if MO2 won't start, run: protontricks $appid -q vcrun2022" >&2
          fi
        fi
      }

      # ------------------------------------------------------------------
      # Steam launch-option mode: `mo2 %command%`. Steam hands us the full
      # runtime+proton+game command line; swap the game exe for MO2's and
      # exec it, so MO2 runs in exactly the invocation the game would have.
      # ------------------------------------------------------------------
      if [ -n "''${STEAM_COMPAT_DATA_PATH:-}" ] && [ "$#" -gt 0 ]; then
        appid="''${SteamAppId:-''${STEAM_COMPAT_APP_ID:-}}"
        if [ -z "$appid" ]; then
          echo "mo2: STEAM_COMPAT_DATA_PATH set but no SteamAppId — running game unmodified" >&2
          exec "$@"
        fi
        inst="$instances_dir/$appid"
        ensure_instance "$appid"

        gamedir=$(game_dir_for "$appid")
        rewritten=() replaced=""
        for a in "$@"; do
          if [ -z "$replaced" ]; then
            case "''${a,,}" in
              *.exe)
                # The game binary — remember it for the plugin stub, swap in
                # MO2, and drop the game's own arguments after it.
                exe_rel=""
                if [ -n "$gamedir" ] && [ "''${a#"$gamedir"/}" != "$a" ]; then
                  exe_rel="''${a#"$gamedir"/}"
                fi
                ensure_game_plugin "$appid" "$inst" "$exe_rel"
                rewritten+=("$inst/ModOrganizer.exe")
                replaced=1
                continue
                ;;
            esac
          elif [ -n "$replaced" ]; then
            continue
          fi
          rewritten+=("$a")
        done

        if [ -z "$replaced" ]; then
          echo "mo2: no .exe in the launch command (native game?) — running unmodified" >&2
          exec "$@"
        fi

        import_shared_creds "$appid" "$STEAM_COMPAT_DATA_PATH/pfx/user.reg"
        inject_settings "$inst"
        echo "$appid" > "$state_dir/last-appid"
        status=0
        "''${rewritten[@]}" || status=$?
        snapshot_settings "$inst"
        export_shared_creds "$appid"
        exit "$status"
      fi

      launch() {
        local appid="$1" inst="$instances_dir/$1"
        ensure_instance "$appid" vcrun
        ensure_game_plugin "$appid" "$inst"
        import_shared_creds "$appid" "$(user_reg_for "$appid")"
        inject_settings "$inst"
        echo "$appid" > "$state_dir/last-appid"
        local status=0
        protontricks-launch --appid "$appid" "$inst/ModOrganizer.exe" || status=$?
        snapshot_settings "$inst"
        export_shared_creds "$appid"
        exit "$status"
      }

      case "''${1:-}" in
        "" | list)
          echo "Installed Steam games (mo2 <name or appid> to launch):"
          list_games | sort -t "$(printf '\t')" -k2 | column -ts "$(printf '\t')"
          ;;

        nxm)
          [ -n "''${2:-}" ] || { echo "usage: mo2 nxm <nxm://...>" >&2; exit 1; }
          appid=$(cat "$state_dir/last-appid" 2>/dev/null || true)
          if [ -z "$appid" ] || [ ! -e "$instances_dir/$appid/ModOrganizer.exe" ]; then
            echo "No MO2 instance has been launched yet — run mo2 <game> first" >&2
            exit 1
          fi
          exec protontricks-launch --appid "$appid" \
            "$instances_dir/$appid/ModOrganizer.exe" "$2"
          ;;

        *)
          query="$*"
          if [[ "$query" =~ ^[0-9]+$ ]]; then
            appid="$query"
          else
            matches=$(list_games | grep -i -- "$query" || true)
            count=$(printf '%s' "$matches" | grep -c . || true)
            if [ "$count" -eq 0 ]; then
              echo "No installed game matches '$query' (try: mo2 list)" >&2
              exit 1
            elif [ "$count" -gt 1 ]; then
              echo "Ambiguous — '$query' matches:" >&2
              echo "$matches" | column -ts "$(printf '\t')" >&2
              exit 1
            fi
            appid=$(printf '%s' "$matches" | cut -f1)
            echo "Launching MO2 for: $(printf '%s' "$matches" | cut -f2) ($appid)"
          fi

          m=$(manifest_for "$appid")
          if [ -z "$m" ]; then
            echo "appid $appid is not installed in any Steam library" >&2
            exit 1
          fi
          if [ ! -d "$(dirname "$m")/compatdata/$appid" ]; then
            echo "No Proton prefix for appid $appid — launch the game once via Steam first" >&2
            exit 1
          fi

          launch "$appid"
          ;;
      esac
    '';
  };

  nxm-handler = pkgs.makeDesktopItem {
    name = "mo2-nxm-handler";
    desktopName = "Mod Organizer 2 NXM handler";
    exec = "mo2 nxm %u";
    mimeTypes = [ "x-scheme-handler/nxm" ];
    noDisplay = true;
  };
in
{
  environment.systemPackages = [
    mo2
    nxm-handler
  ];

  xdg.mime.defaultApplications."x-scheme-handler/nxm" = "mo2-nxm-handler.desktop";
}

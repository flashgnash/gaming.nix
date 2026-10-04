{ pkgs, ... }:
let
  # Space Marine 2 crashes mid-mission on kernel 7.2+ (access violation on the
  # resFILE_LOADER thread): the game waits on a file-load future with a single
  # unlooped SleepConditionVariableCS(INFINITE), and Wine's RtlWaitOnAddress
  # leaves a stale thread alert behind when a wake races a timed-out
  # zero-timeout wait (which the game's tcmalloc issues constantly), so that
  # "infinite" wait returns early and a read callback writes into a dead stack
  # frame. Kernel 7.2 only made the race frequent. Proton version swaps and
  # ntsync toggles do NOT help — the fix has to be in Wine itself.
  #
  # This is Proton 11.0-2c plus jegglest's prototype ntdll/wineserver patches
  # (WineHQ bugs 60397 + 60417, diagnosis in ValveSoftware/Proton#8072).
  # Force it for SM2 only: game properties → Compatibility →
  # "SM2_20261002_ntdll_and_abandon_mutexes_prototype_fix".
  #
  # Remove once the fix lands upstream (watch WineHQ 60397 / Proton releases /
  # SM2 patch notes — Saber ticket 12458 would also make the game immune).
  sm2-proton-fix = pkgs.fetchzip {
    name = "SM2_20261002_ntdll_and_abandon_mutexes_prototype_fix";
    url = "https://github.com/Jpokul/prototype_SM2_proton_fix_patch14-15/releases/download/Zip/SM2_20261002_ntdll_and_abandon_mutexes_prototype_fix.zip";
    hash = "sha256-sx9hGbSWWuu8BAmeL+NYOJyS5Cd4C3TItiI5ccW7xlI=";
  };
in
{
  programs.steam.extraCompatPackages = [ sm2-proton-fix ];
}

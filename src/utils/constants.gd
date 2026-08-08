extends Node

## Global constants for RiotSwitcher

# Riot Client & Process Names
const PROCESS_RIOT_CLIENT: String = "Riot Client.exe"
const PROCESS_VALORANT: String = "VALORANT.exe"
const PROCESS_LEAGUE: String = "LeagueClient.exe"
const PROCESS_VANGUARD: String = "vgtray.exe"

# Riot Registry Keys
const REG_RIOT_CLIENT_PATH: String = "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Riot Client"
const REG_VAL_PATH: String = "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Riot Game valorant.live"
const REG_LOL_PATH: String = "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Riot Game league_of_legends.live"

# Default App Settings
const DEFAULT_AUTOSTART: bool = false
const DEFAULT_CLOSE_TO_TRAY: bool = true
const DEFAULT_MINIMIZE_TO_TRAY: bool = true
const DEFAULT_LANGUAGE: String = "pt_BR"
const DEFAULT_SYNC_GAME_SETTINGS: bool = false
const DEFAULT_DIRECT_LAUNCH: bool = true

# UI & Animation Timings
const TWEEN_DURATION_FAST: float = 0.15
const TWEEN_DURATION_NORMAL: float = 0.25
const CARD_HOVER_SCALE: Vector2 = Vector2(1.03, 1.03)
const CARD_NORMAL_SCALE: Vector2 = Vector2(1.0, 1.0)

# Colors
const COLOR_PRIMARY: Color = Color("d32f2f")
const COLOR_BG_DARK: Color = Color("0f0f12")
const COLOR_CARD_BG: Color = Color("1a1a20")
const COLOR_ACCENT: Color = Color("ff4655")

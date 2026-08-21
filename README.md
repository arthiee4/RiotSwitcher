# Riot Switcher

**⚠️ IMPORTANT SECURITY NOTICE:**

**Always download Riot Switcher ONLY from the official source.**  
**Do NOT trust unknown links or unofficial websites.**  
Downloading from untrusted sources may compromise your computer's security.

---

<p align="center">
  <img src="assets/example-vANA.webp" alt="Stay Signed In Guide">
</p>

## Riot Switcher

**Riot Switcher** is a custom launcher created for League of Legends players to manage multiple accounts in a simple, fast, and organized way.

> **Note:** Riot Switcher is currently only available for League of Legends. Valorant support is planned for future updates.

## Main Features

- Manage multiple accounts separately.
- Log in to any account with just **one click**.
- Instantly switch the game's language (voice and text). *(Feature planned for future updates)*
- Basic Vanguard core control support.

## How It Works

1. **Save Current Account:** Captures local credentials from the Riot Client.
2. **Switch Account:** Copies the selected profile to the client's folder.
3. **Automatic Login:** Riot Client opens directly in the chosen account.
4. **Updates:** Future support for profile updates, per-account language settings, and additional integrations.

## 🧐 How to Use Riot Switcher Properly

After creating your account profile inside Riot Switcher, click on the **Play** button for the selected profile.

When the Riot Client opens:
- Log in normally.
- **IMPORTANT:** Make sure to check the **"Stay signed in"** checkbox before logging in.

If you don't check "Stay signed in," Riot Switcher won't be able to handle automatic login properly in the future.

### Quick Steps:
1. Create your account profile.

<p align="center">
  <img src="assets/example2-vANA.webp" alt="Create Profile Example">
</p>

2. Go to Home, and press play button on the account.
3. **IMPORTANT:** On the Riot login screen, **check "Stay signed in"** and log in. This step is crucial for automatic login to work!

![Stay Signed In Guide](assets/stay_signed_in.gif)

Done! Your account is ready for one-click switching.

## Requirements

- Windows 10/11
- Installed Riot Games Client
- Administrator permissions (recommended for file copying and process management)

## Project Status

> Actively under development — currently focusing on bug fixes and new features. Future plans include Valorant integration, per-account language settings, and enhanced client management.

## How to Build the Project

The project is developed using **Godot Engine**, a powerful open-source game engine.

There are two ways to build Riot Switcher: the **automated Python builder** (recommended) or the manual editor export.

### Automated Build (Python) — Recommended

A small Python script exports the project, compresses the executable with **UPX** and zips everything into a release named `RiotSwitcher-<version>.zip`.

**What you need:**

- **Python 3.10+** — no extra libraries required, the script uses only Python's standard library (no `pip install` needed).
- **Godot editor** — found automatically: the script scans GodotHub installs, the official `Programs\Godot` folder and the PATH, and picks the editor matching the version required by the project. If your setup is different, set the `GODOT_EDITOR` environment variable or fill the `EXTRA_GODOT_PATHS` list at the top of the script.
- **UPX** — found automatically in the PATH or in the bin folder next to the custom Godot template; override with the `UPX_PATH` environment variable if needed.
- **The custom lightweight template** — already configured in `export_presets.cfg`; its build recipe lives in `build/custom.py` + `build/build_profile.build` in case you ever want to recompile it.

**Simple steps:**

1. Open a terminal in the project folder.
2. Run the script with the version you want:

   ```bash
   python build/build_release.py 0.3.4
   ```

   (Or just `python build/build_release.py` — it will ask for the version.)
3. Done! The script exports the game headlessly, runs `upx --best` on the executable and creates the release next to the script:

   ```
   build/RiotSwitcher-0.3.4.zip
   ```

### Manual Build (Godot Editor)

To build Riot Switcher by hand:

1. **Download Godot Engine:** [Official Website](https://godotengine.org/)
2. **Open the Project:** Launch Godot, click "Import Project" and select the Riot Switcher project folder.
3. **Make Adjustments (Optional):** Modify settings or scenes if needed.
4. **Export the Build:**
   - Open **Project > Export**.
   - Add a **Windows Desktop** preset (or others if needed).
   - Click **Export Project** to generate the executable.
   - All user data and profile backups are automatically saved in `user://` (`%APPDATA%`), making the executable fully portable and independent!

## About Godot Engine

- **No need for external build systems** — everything is managed inside the editor.
- **Cross-platform** — easily deploy to Windows, Linux, Mac, Web, and more.
- **Lightweight builds** — small and efficient executables.
- **Active community** — continuous improvements and new features.

## License and Disclaimer

This is a personal project created for educational and organizational purposes only.

**Riot Switcher is not affiliated, associated, authorized, endorsed by, or in any way officially connected with Riot Games, Inc., or any of its subsidiaries or affiliates.**

All product and company names are trademarks™ or registered® trademarks of their respective holders. The use of these names, logos, and brands does not imply endorsement.

**Use of Riot Switcher is at your own risk. The developer does not take responsibility for any consequences, including penalties or bans, resulting from its use.**

Made with ❤️ using Godot Engine.

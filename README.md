# EHTweaks

**EHTweaks** is a collection of UI enhancements and quality-of-life improvements designed specifically for the Project Ebonhold custom character progression system.

It extends the default Project Ebonhold interface with searching, filtering, build management, and browsing capabilities to help you plan and manage your classless builds more effectively.

## Features

### 📋 Loadout Manager
*   **Local Build Storage**: Save your Skill Tree builds locally.
*   **Metadata Support**: Give your builds custom names and multi-line descriptions (perfect for keeping track of build requirements or rotation tips).
*   **Icon Selector**: Choose a unique icon for every build using a macro-style grid containing every icon found in the Skill Tree database plus generic class icons.
*   **Auto-Backup**: EHTweaks automatically saves a snapshot of your current build before you perform a Reset or Apply a new loadout (stores up to 2 backups).
*   **Override Selected Loadout**: Override the currently selected Loadout without re-picking it.
*   **Quick Save**: Shift+Click **Save** to instantly create a backup and override (skips the popup dialog).
*   **Quick Switch**: Use `/ehtload Loadout Name` to switch loadouts instantly via chat or macros.
*   **Sharing**: Easily Export or Import builds via compressed text strings to share your creations with other EHTweaks users.

### 🔄 Fail-Safe Tree Reset
*   **Reliable Refunds**: Adds a "Reset Tree" button to the bottom bar.
*   **Logic**: EHTweaks clears your tree by applying a 1-point starter build, ensuring 100% reliability for Soul Ash refunds (this is a workaround for now - you can manually refund the last skill).

### 🔍 Skill Tree Filtering
*   **Search Box**: Adds a filter input to the Skill Tree window.
*   **Smart Search**: Filters by both Ability Name and Description.
*   **Visual Feedback**: Matching nodes pulse with a green glow, while non-matching nodes are dimmed.
*   **Node Focus**: Press **Enter** in the search box to automatically jump to and center the first match in the tree.
*   **Keybind Support**: Skill Tree Open/Close can now be bound in the WoW Key Bindings menu.

(alpha 0.0.1)

![ETH tweaks 1](https://raw.githubusercontent.com/mmobrain/stuffforstuff/main/ETHtweaks_stuff/1.gif)

### 📚 Ebonhold Compendium (The Browser)
*   **Skill Tree Tab**: A searchable list of every node available in the tree.
*   **My Echoes Tab**: View all your collected Perks (Echoes) in one consolidated list.
*   **Jump-to-Tree**: Clicking a skill in the browser automatically opens the Skill Tree, scrolls to that node, and highlights it with an orange pulsing glow.
*   **Favored Echos**: Right-click ("Echoes Browser") or Shift+Right-click ("My Echoes", "Echo selection/draft UI") an Echo to mar it as **FAVOURED** it; favored Echoes are pinned to the top and marked with a diamond icon and "FAVOURED" label.
*   **Quick Access**: Open "My Echoes" by clicking the "E" button on the custom MiniRunBar.

(alpha 0.0.3)

![ETH tweaks 2](https://raw.githubusercontent.com/mmobrain/stuffforstuff/main/ETHtweaks_stuff/2.gif)


### 🪄 Smart Tooltips
*   **Rank Merging**: In the Compendium, skills with multiple ranks combine values into a single view (e.g., "Deals 10/20/30 damage") so you can see the full progression at a glance.

### 💎 Echoes Filter
*   Adds a filter bar to the bottom of the **Echoes (Empowerment)** frame to quickly find specific perks in your collection.

(alpha 0.0.1)

![ETH tweaks 3](https://raw.githubusercontent.com/mmobrain/stuffforstuff/main/ETHtweaks_stuff/1.jpg)

### 🧭 Enhanced Objective Tracker
*   Integrated the custom Objectives system into the Project Ebonhold Soul Ash HUD for better tracking.

### ☣ Hazard Warning
*   Warns immediately upon (own) Shadow Fissure (red circle) spawn

![ETH tweaks 4](https://raw.githubusercontent.com/mmobrain/stuffforstuff/refs/heads/main/ETHtweaks_stuff/3.jpg)

### ↗️ Movable HUD elements
*   The **"Choose an Echo"** and **"Hide/Show"** buttons are now movable via **Shift+Drag** and share the same saved coordinate.
*   The **Soul Ash HUD** (`playerRunFrame`) position is saved across sessions.
*   **Minimize**: ProjectEbonhold Player Run Frame can be minimized to a thin bar.

(alpha 0.0.5)

![ETH tweaks 5](https://raw.githubusercontent.com/mmobrain/stuffforstuff/main/ETHtweaks_stuff/2.jpg)

## Commands
*   `/eht` - Open the Ebonhold Compendium (Browser).
*   `/eht reset` - Wipes the internal browser cache (useful if the server updates the tree).
*   `/ehtload Loadout Name` - Switch loadouts instantly via chat or macros.

## Keybinds
*   **Skill Tree Open/Close** - Available in the WoW Key Bindings menu.
*   **Toggle My Echoes** - Available in the WoW Key Bindings menu.

## Other QOL
*   `Ctrl+Alt+click` - Link Echo or Skill to chat.

## Installation
1. Download the repository.
2. Extract the folder into your World of Warcraft `Interface/AddOns/` directory.
3. Ensure the folder is named exactly `EHTweaks`.
4. Requires the **ProjectEbonhold** core addon and **LibDeflate** (included in libs) to be enabled.

## Requirements
*   **Game Version**: 3.3.5a (Wrath of the Lich King)
*   **Server**: Project Ebonhold

## Credits
*   **Skulltrail:** Author
*   **Xurkon:** UI Reskin & Fixes
*   **MedianAura:** Features - Hide minimap button, Screen warning on death for permanent echoes.

## License
This project is released under the [MIT License](LICENSE.md).

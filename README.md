# EHTweaks

**EHTweaks** is a collection of UI enhancements and quality-of-life improvements designed specifically for the Project Ebonhold custom character progression system. 

It extends the default Project Ebonhold interface with searching, filtering, and browsing capabilities to help you plan and manage your classless builds more effectively.

## Features

### 🔍 Skill Tree Filtering
*   **Search Box**: Adds a filter input to the Skill Tree window.
*   **Smart Search**: Filters by both Ability Name and Description.
*   **Visual Feedback**: Matching nodes pulse with a green glow, while non-matching nodes are dimmed.
*   **Node Focus**: Press **Enter** in the search box to automatically jump to and center the first match in the tree.

(alpha 0.0.1)

![ETH tweaks 1](https://raw.githubusercontent.com/mmobrain/stuffforstuff/main/ETHtweaks_stuff/1.gif)

### 📚 Ebonhold Compendium (The Browser / Ebonhold Compendium)
*   **Skill Tree Tab**: A searchable list of every node available in the tree. 
*   **My Echoes Tab**: View all your collected Perks (Echoes) in one consolidated list.
*   **Jump-to-Tree**: Clicking a skill in the browser automatically opens the Skill Tree, scrolls to that node, and highlights it with an orange pulsing glow.

(alpha 0.0.3)

![ETH tweaks 2](https://raw.githubusercontent.com/mmobrain/stuffforstuff/main/ETHtweaks_stuff/2.gif)

*   **Echoes DB tab**: View all known Perks (Echoes) in one consolidated list.
*   **Import/Export tab**: You can now share your or apply external data.

(alpha 0.0.5)

![ETH tweaks 4](https://raw.githubusercontent.com/mmobrain/stuffforstuff/main/ETHtweaks_stuff/3.gif)

### 🪄 Smart Tooltips
*   **Rank Merging**: For skills with multiple ranks, the browser combines values into a single view (e.g., "Deals 10/20/30 damage") so you can see the full progression at a glance.

### 💎 Echoes Filter
*   Adds a filter bar to the bottom of the **Echoes (Empowerment)** frame to quickly find specific perks in your collection.

(alpha 0.0.1)

![ETH tweaks 3](https://raw.githubusercontent.com/mmobrain/stuffforstuff/main/ETHtweaks_stuff/1.jpg)

### 🧭 Enhanced Objective Tracker
*   Integrated the new Objectives system into the Project Ebonhold Soul Ash HUD.

### ↗️ Movable HUD elements
*   The **"Choose an Echo"** and **"Hide/Show"** buttons are now movable via **Shift+Drag** and share the same saved coordinate.
*   The **Soul Ash HUD** (`playerRunFrame`) position is saved across sessions.

(alpha 0.0.5)

![ETH tweaks 5](https://raw.githubusercontent.com/mmobrain/stuffforstuff/main/ETHtweaks_stuff/2.jpg)


## Commands

*   `/eht` - Open the Ebonhold Compendium (Browser).
*   `/eht reset` - Wipes the internal browser cache (useful if the server updates the tree).

## Other QOL
*   `Ctrl+Alt+click` - Link Echo or Skill to chat.

## Installation

1. Download the repository.
2. Extract the folder into your World of Warcraft `Interface/AddOns/` directory.
3. Ensure the folder is named exactly `EHTweaks`.
4. Requires the **ProjectEbonhold** core addon to be enabled.

## Requirements
*   **Game Version**: 3.3.5a (Wrath of the Lich King)
*   **Server**: Project Ebonhold

## Credits
*   **Author:** Skulltrail

## License
This project is released under the [MIT License](LICENSE.md).


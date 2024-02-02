# PowerShell IP Configuration GUI

This PowerShell script provides a user-friendly GUI for quickly changing IP addresses on Windows machines without the need for repeated User Account Control (UAC) prompts. It includes features for storing IP configuration profiles for easy reuse.

## Features

- **Graphical User Interface**: Simplifies the process of changing IP addresses and network settings.
- **Profile Management**: Save and manage multiple network profiles for quick switching.
- **UAC Prompt Avoidance**: Designed to minimize the need for UAC prompts through efficient permission usage.

## Requirements

- Membership in the **"Network Configuration Operators"** group is required to change IP settings without elevated privileges.
- **PowerShell 5.1** (it may work on higher versions too - untested).
- **Windows 10/11**.

## Setup Instructions

1. **Download**: Download the script and extract it to a desired location on your computer.
2. **Shortcut Creation**: For convenient access, create a shortcut to the batch file included with the script. Right-click the shortcut, go to `Properties -> Advanced`, and check the "Run as administrator" option.
3. **Launch**: Double-click the shortcut to launch the GUI.

## Usage

- **Changing IP Settings**: Select a network adapter, choose a profile (or create a new one), and apply the settings.
- **Profile Management**: Easily save current settings as a new profile for future use. Profiles include IP address, subnet mask, and gateway configurations.

## Script Overview

The script uses Windows Forms and Drawing libraries to create the GUI, allowing users to interact with network settings visually. It includes functions for:

- Enumerating network adapters.
- Saving and applying IP configuration profiles.
- Dynamically updating the GUI based on selected profiles and adapters.

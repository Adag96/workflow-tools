# Workflow Tools

Personal configuration files for macOS workflow tools.

## Installation

Clone the repository and run the install script:

```bash
git clone git@github.com:Adag96/workflow-tools.git ~/workflow-tools
~/workflow-tools/install.sh

TOOLS:
- Yabai: window tiling management
- Sketchybar: status bar customization

----- ABLETON PROJECT TIMER SYNCHRONIZATION -----
The Ableton Project Timer tracks project time across multiple machines. To maintain consistency:

1. Initial Setup
- The timer state is stored in sketchybar/timer_data/timer_state.json
- Each machine gets a local copy of this file during installation
2. Synchronizing Between Machines
- Manually commit and push timer state changes to the repository
- Pull changes on other machines
- Run install.sh to update the local timer state file

Best Practices
- Commit timer state changes before switching machines
- Avoid concurrent modifications on different machines
- If timer states diverge, manually merge the JSON file
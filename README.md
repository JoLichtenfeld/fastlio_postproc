# fastlio_postproc

This helper script walks you through the Fastlio settings by detecting the available topics in a bagfile.
If PointCloud2 and LivoxCustomMsg topics are present, you can choose which one to use.

### Build
- clone this repo
- colcon build

### Usage
```fastlio_postproc <bagfile>```

Then just follow the terminal UI prompts.
This will spawn a tmux session with panes for Fastlio, bag player and Rviz.

### Dependencies
tmux is required (sudo apt install tmuxp).

# Game Boy: RGBDS Exporter for Aseprite

This is a small script for exporting your Aseprite graphics into an ASM
format for use within RGBDS.


## Installation

Copy the `.lua` script to the Aseprite `scripts` directory and restart Aseprite.


## Usage

**IMPORTANT: use an indexed palette of only 4 colours**

There are several export options for maximum flexibility.

* Export Mode: **Full Canvas (Grid)**
  - Tile Sizes: `8x8`, `8x16`, `16x16`, `32x32`
  - Parse direction (canvas): Vertical or Horizontal
* Export Mode: **By Slices**
  - Sort Slices: Position or Name
  - When using "Name" sprites are sorted alphabetically, otherwise by canvas position
  - When using "Name" ASM labels will use that value, e.g. `RocketU1::`
* Output Format: **RGBDS DW** or **Standard HEX (DB)**
  - each tile is given a comment with its number, e.g. `Tile 0x3C`
* Add ASM Labels:
  - prefixes each sprite with an ASM label, e.g. `Sprite01::`
* Remove Duplicates
* Current Frame Only
* A default output filename is used and saved in the same directory as the input file

At the top of the script is a `defaultConfig`. Change this to your preferred
default settings.


## License

Copyright (c) 2026 Michael R. Cook. All rights reserved.

This work is licensed under the terms of the MIT license.
For a copy, see <https://opensource.org/licenses/MIT>.

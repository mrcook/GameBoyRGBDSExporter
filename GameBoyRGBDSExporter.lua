--[[
  Game Boy: RGBDS Exporter
  Michael R. Cook
 
  This script will export an image to a RGBDS compatible assembly format.
 
  *********************************************************
  ** IMPORTANT: use an indexed palette of only 4 colours **
  *********************************************************
 
  Example: the number 1
 
  DW `00000000
  DW `00033000
  DW `00303000
  DW `00003000
  DW `00003000
  DW `00003000
  DW `00333330
  DW `00000000
 
  ## v1.1 (2026-01-18)
 
  * Export by "Slices" using Position or slice Name
  * Add ASM labels, e.g. "Sprite04::" or "Player::" when using Slices + names
  * Add sprite comments, e.g. "; Tile 0x4B"
 
  ## v1.0 (2026-01-11)
 
  * Output: RGBDS DW or Standard HEX (DB) formats
  * Export tile sizes: 8x8, 8x16, 16x16, 32x32
  * Parse direction (canvas): vertical or horizontal
]]

-- use your own default configuration here:
local defaultConfig < const > = {
  mode = "Full Canvas (Grid)",
  tileSize = "8x8", direction = "Horizontal", sortBy = "Name",
  format = "RGBDS DW", asmLabels = true, dedupe = true, onlyCurrent = true
}

-- Image must use an indexed palette
if not app.activeSprite or app.activeSprite.colorMode ~= ColorMode.INDEXED then
  app.alert("Requires an Indexed Sprite.") return
end

function processData(args, sprite)
  -- Determine tile dimensions
  local tW, tH = 8, 8
  if args.tileSize == "8x16" then tH = 16
  elseif args.tileSize == "16x16" then tW, tH = 16, 16
  elseif args.tileSize == "32x32" then tW, tH = 32, 32
  end

  -- Validate sprite alignment
  if (sprite.width % tW ~= 0 or sprite.height % tH ~= 0) and args.mode ~= "By Slices" then
    return app.alert(string.format("Sprite must be multiple of %dx%d.", tW, tH))
  end

  -- main conversion logic
  local uniqueTiles, tileOrderedList, maps = {}, {}, {}
  local nextID = 0
  local frameList = args.onlyCurrent and {app.activeFrame} or sprite.frames

  local img = Image(sprite.spec)
  local step = 0 -- set with region discovery

  for _, frame in ipairs(frameList) do
    local frameMap = {}
    img:clear()
    img:drawSprite(sprite, frame)

    local regions = {}

    -- collect the sprites based on their mode/format
    if args.mode == "By Slices" then
      if #sprite.slices == 0 then app.alert("No slices found!") return end

      local sortedSlices = {}
      for _, s in ipairs(sprite.slices) do
        table.insert(sortedSlices, s)
      end

      table.sort(sortedSlices, function(a, b)
        if args.sortBy == "Name" then
          return string.lower(a.name) < string.lower(b.name)
        end
        return a.bounds.y < b.bounds.y or (a.bounds.y == b.bounds.y and a.bounds.x < b.bounds.x)
      end)

      for _, s in ipairs(sortedSlices) do
        table.insert(regions, {x = s.bounds.x, y = s.bounds.y, w = s.bounds.width, h = s.bounds.height, name = s.name})
      end
      step = #regions
    else
      local w, h = sprite.width, sprite.height
      if args.direction == "Horizontal" then
        for y = 0, h - 1, tH do
          for x = 0, w - 1, tW do
            table.insert(regions, {x = x, y = y, w = tW, h = tH, name = string.format("%d,%d", x, y)})
          end
        end
        step = w / tW
      else
        for x = 0, w - 1, tW do
          for y = 0, h - 1, tH do
            table.insert(regions, {x = x, y = y, w = tW, h = tH, name = string.format("%d,%d", x, y)})
          end
        end
        step = h / tH
      end
    end

    -- generate the correct output format + sprite header details
    for i, reg in ipairs(regions) do
      local data = getTileData(img, reg.x, reg.y, reg.w, reg.h, args.format)
      local label = ""
      if args.asmLabels then
        if args.mode == "By Slices" and args.sortBy == "Name" then
          label = string.format("%s:: ; Tile 0x%02X\n", reg.name, i)
        else
          label = string.format("Sprite%02X:: ; Tile 0x%02X\n", i, i)
        end
      else
        label = string.format("; Tile 0x%02X | Pos: %s\n", i, reg.name)
      end

      if args.dedupe then
        if not uniqueTiles[data] then
          uniqueTiles[data] = nextID
          table.insert(tileOrderedList, label .. data)
          nextID = nextID + 1
        end
        table.insert(frameMap, uniqueTiles[data])
      else
        table.insert(tileOrderedList, label .. data)
        table.insert(frameMap, nextID)
        nextID = nextID + 1
      end
    end

    table.insert(maps, frameMap)
  end

  -- Write all tiles to the file
  local f = io.open(args.tileFile, "w")
  f:write("; Game Boy: RGBDS Exporter v1.1 by mrcook\n;\n")

  f:write(string.format("; Input file: %s\n", app.fs.fileName(app.activeSprite.filename)))
  if args.mode == "By Slices" then
    f:write(string.format("; Export By Slices | Sort By %s", args.sortBy))
  else
    f:write(string.format("; Export %s Tiles | %s", args.tileSize, args.direction))
  end
  if args.dedupe then
    f:write(" | de-duped")
  end
  f:write("\n\n")

  if args.asmLabels then f:write("Tiles::\n\n") end
  f:write(table.concat(tileOrderedList, "\n\n"))
  if args.asmLabels then f:write("\n\nTilesEnd::") end
  f:close()

  app.alert("Export Complete!")
end

-- Breaks larger tiles into 8x8 sub-tiles
function getTileData(img, x, y, w, h, format)
  local subTiles = {}

  local formatter = get8x8Hex
  if format == "RGBDS DW" then
    formatter = get8x8DW
  end

  for tx = 0, w - 1, 8 do
    for ty = 0, h - 1, 8 do
      table.insert(subTiles, formatter(img, x + tx, y + ty))
    end
  end

  return table.concat(subTiles, "\n")
end

-- Generates an RGBDS string for a single 8x8 tile
function get8x8DW(img, x, y)
  local rows = {}
  for cy = 0, 7 do
    local row = {}
    for cx = 0, 7 do
      table.insert(row, img:getPixel(x + cx, y + cy) & 3)
    end
    table.insert(rows, "DW `" .. table.concat(row))
  end
  return table.concat(rows, "\n") .. "\n"
end

-- Generates 8x8 tile in HEX format (All 16 bytes on one line)
function get8x8Hex(img, x, y)
  local bytes = {}
  for cy = 0, 7 do
    local lo, hi = 0, 0
    for cx = 0, 7 do
      local px = img:getPixel(x + cx, y + cy) & 3
      if (px & 1) ~= 0 then lo = lo | (1 << (7 - cx)) end
      if (px & 2) ~= 0 then hi = hi | (1 << (7 - cx)) end
    end
    table.insert(bytes, string.format("$%02x", lo))
    table.insert(bytes, string.format("$%02x", hi))
  end
  return "DB " .. table.concat(bytes, ",")
end

function showExportDialogue(prevCfg)
  local dlg = Dialog("Game Boy: RGBDS Exporter v1.1")

  local sprite = app.activeSprite
  -- If no previous config is present, set some defaults
  local cfg = prevCfg or defaultConfig

  -- Parse the current image filename
  local path = app.fs.filePath(sprite.filename)
  local title = app.fs.fileTitle(sprite.filename)

  -- Set default filename using the same directory as the .ase file
  local defaultTilePath = app.fs.joinPath(path, title .. "-tiles.inc")
  dlg:file{id = "tileFile", label = "Output File", save = true, filename = defaultTilePath, filetypes = {"asm", "inc"}}
  dlg:separator()

  dlg:combobox{
    id = "mode", label = "Export Mode:", option = cfg.mode, options = {"Full Canvas (Grid)", "By Slices"},
    onchange = function()
      -- close and re-open dialogue using current config
      local currentCfg = dlg.data
      currentCfg.bounds = dlg.bounds -- capture current dialogue position

      dlg:close()
      showExportDialogue(currentCfg)
    end
  }

  -- Toggle options visibility based on the export mode
  local isSlices = (cfg.mode == "By Slices")
  -- Full canvas mode:
  dlg:combobox{id = "tileSize", label = "Tile Size:", option = cfg.tileSize, options = {"8x8", "8x16", "16x16", "32x32"}, visible = not isSlices}
  dlg:combobox{id = "direction", label = "Parse Direction:", option = cfg.direction, options = {"Horizontal", "Vertical"}, visible = not isSlices}
  -- Slices mode:
  dlg:combobox{id = "sortBy", label = "Sort Slices:", option = cfg.sortBy, options = {"Position", "Name"}, visible = isSlices}
  dlg:separator()

  dlg:combobox{id = "format", label = "Output Format:", option = cfg.format, options = {"RGBDS DW", "Standard HEX (DB)"}}
  dlg:check{id = "asmLabels", label = "Add ASM labels", selected = cfg.asmLabels}
  dlg:separator()
  dlg:check{id = "dedupe", label = "Remove Duplicates", selected = cfg.dedupe}
  dlg:check{id = "onlyCurrent", label = "Current Frame Only", selected = cfg.onlyCurrent}
  dlg:button{id = "ok", text = "Export", focus = true}
  dlg:button{id = "cancel", text = "Cancel"}

  -- Restore the original position of the dialogue
  if cfg.bounds then
    dlg:show{wait = true, bounds = cfg.bounds}
  else
    dlg:show()
  end

  if not dlg.data.ok or dlg.data.tileFile == "" then return end

  processData(dlg.data, sprite)
end

showExportDialogue()

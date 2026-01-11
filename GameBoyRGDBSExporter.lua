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
 
  * Supports both RGBDS DW and Standard HEX (DB) formats
  * Supports tile sizes: 8x8, 8x16, 16x16, 32x32
  * Parse direction: vertical or horizontal
]]
local sprite = app.activeSprite
sprite.data = "MyCustomName"
local exportName = (sprite.data ~= "") and sprite.data or app.fs.fileTitle(sprite.filename)

-- Image must use an indexed palette
if not sprite or sprite.colorMode ~= ColorMode.INDEXED then
  app.alert("Requires an Indexed Sprite.") return
end

-- Parse the current image filename
local path = app.fs.filePath(sprite.filename)
local title = app.fs.fileTitle(sprite.filename)

-- Set default filenames, using the same directory as the .ase file
local defaultTilePath = app.fs.joinPath(path, title .. "-tiles.inc")
local defaultMapPath = app.fs.joinPath(path, title .. "-map.inc")

-- Dialogue for tile size, parse direction, and files
local dlg = Dialog("Game Boy: RGBDS Exporter v1.0")
dlg:file{id = "tileFile", label = "Tiles File", save = true, filename = defaultTilePath, filetypes = {"asm", "inc"}}
dlg:file{id = "mapFile", label = "Tilemap File", save = true, filename = defaultMapPath, filetypes = {"asm", "inc"}}
dlg:separator()
dlg:combobox{id = "tileSize", label = "Tile Size:", option = "8x8", options = {"8x8", "8x16", "16x16", "32x32"}}
dlg:combobox{id = "direction", label = "Parse Direction:", option = "Horizontal", options = {"Horizontal", "Vertical"}}
dlg:combobox{id = "format", label = "Output Format:", option = "RGBDS DW", options = {"RGBDS DW", "Standard HEX (DB)"}}
dlg:check{id = "dedupe", label = "Remove Duplicates", selected = true}
dlg:separator()
dlg:check{id = "onlyCurrent", label = "Current Frame Only", selected = true}
dlg:button{id = "ok", text = "Export", focus = true}
dlg:button{id = "cancel", text = "Cancel"}
dlg:show()

local args = dlg.data
if not args.ok or args.tileFile == "" then return end

-- Determine tile dimensions
local tW, tH = 8, 8
if args.tileSize == "8x16" then tH = 16
elseif args.tileSize == "16x16" then tW, tH = 16, 16
elseif args.tileSize == "32x32" then tW, tH = 32, 32
end

-- Validate sprite alignment
if (sprite.width % tW) ~= 0 or (sprite.height % tH) ~= 0 then
  app.alert(string.format("Sprite size must be a multiple of %dx%d.", tW, tH)) return
end

-- Generates an RGBDS string for a single 8x8 tile
local function get8x8DW(img, x, y)
  local rows = {}
  for cy = 0, 7 do
    local row = {}
    for cx = 0, 7 do
      row[cx + 1] = img:getPixel(x + cx, y + cy) & 3
    end
    table.insert(rows, "DW `" .. table.concat(row))
  end
  return table.concat(rows, "\n") .. "\n"
end

-- Generates 8x8 tile in HEX format (All 16 bytes on one line)
local function get8x8Hex(img, x, y)
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

-- Breaks larger tiles into 8x8 sub-tiles
local function getTileData(img, x, y, w, h, format)
  local subTiles = {}

  local formatter = get8x8Hex
  if format == "RGBDS DW" then
    formatter = get8x8DW
  end

  for tx = 0, w - 1, 8 do
    for ty = 0, h - 1, 8 do
      local data = formatter(img, x + tx, y + ty)
      table.insert(subTiles, data)
    end
  end

  return table.concat(subTiles, "\n")
end

-- Main processing logic
local uniqueTiles = {}
local tileOrderedList = {}
local maps = {}
local nextID = 0
local frameList = args.onlyCurrent and {app.activeFrame} or sprite.frames

for _, frame in ipairs(frameList) do
  local frameMap = {}
  local img = Image(sprite.spec)
  img:drawSprite(sprite, frame)

  local w, h = sprite.width, sprite.height
  local xRange = (args.direction == "Horizontal") and {0, h - 1, tH, 0, w - 1, tW} or {0, w - 1, tW, 0, h - 1, tH}

  if args.direction == "Horizontal" then
    for y = 0, h - 1, tH do
      for x = 0, w - 1, tW do
        local data = getTileData(img, x, y, tW, tH, args.format)
        if args.dedupe then
          if not uniqueTiles[data] then
            uniqueTiles[data] = nextID
            table.insert(tileOrderedList, data)
            nextID = nextID + 1
          end
          table.insert(frameMap, uniqueTiles[data])
        else
          table.insert(tileOrderedList, data)
          table.insert(frameMap, nextID)
          nextID = nextID + 1
        end
      end
    end
  else -- Vertical Parse
    for x = 0, w - 1, tW do
      for y = 0, h - 1, tH do
        local data = getTileData(img, x, y, tW, tH, args.format)
        if args.dedupe then
          if not uniqueTiles[data] then
            uniqueTiles[data] = nextID
            table.insert(tileOrderedList, data)
            nextID = nextID + 1
          end
          table.insert(frameMap, uniqueTiles[data])
        else
          table.insert(tileOrderedList, data)
          table.insert(frameMap, nextID)
          nextID = nextID + 1
        end
      end
    end
  end
  table.insert(maps, frameMap)
end

-- Write all tiles to the file
local f = io.open(args.tileFile, "w")
f:write(string.format("; %s | %s Tiles | %s | %s | Deduped: %s\n", title, args.tileSize, args.direction, args.format, args.dedupe))
f:write(table.concat(tileOrderedList, "\n\n"))
f:close()

-- Write tilemap to the file
if args.mapFile ~= "" then
  local mf = io.open(args.mapFile, "w")
  for i, frameMap in ipairs(maps) do
    mf:write(string.format("; Frame %d Map\n", i))
    local step = (args.direction == "Horizontal") and (sprite.width / tW) or (sprite.height / tH)
    for start = 1, #frameMap, step do
      local line = {}
      for k = 0, step - 1 do
        table.insert(line, string.format("$%02x", frameMap[start + k]))
      end
      mf:write("DB " .. table.concat(line, ", ") .. "\n")
    end
    mf:write("\n")
  end
  mf:close()
end

app.alert("Export Complete!")

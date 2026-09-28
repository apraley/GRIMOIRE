-- Text metrics + Playdate text markup for the headless mock/renderer.
-- Shared by tools/pdmock.lua (width/height queries) and tools/pdraster.lua
-- (actual glyph drawing), so layout computed headlessly matches screenshots.
--
-- Markup (playdate.graphics.drawText / getTextSize): "*" toggles bold, "_"
-- toggles italic; "**" and "__" produce a literal "*" / "_".
-- font:drawText / font:getTextWidth use the raw font (no markup).

local DIR = PD_TOOLS_DIR or ((arg and arg[0] and arg[0]:match("(.*/)")) or "./")
local FONT = dofile(DIR .. "pdfont.lua")

local T = { height = FONT.height, font = FONT }
local V = FONT.variants

local function glyph(variant, c)
  local g = V[variant] or V.normal
  return g[c] or g[63] -- '?' for anything the font lacks
end
T.glyph = glyph

-- split into lines; each line is a list of { code, variant } (markup applied
-- when `markup` is true, starting from `base` variant)
function T.layout(s, base, markup)
  s = tostring(s)
  base = base or "normal"
  local lines, cur = {}, {}
  local bold = base == "bold"
  local italic = base == "italic"
  local i, n = 1, #s
  while i <= n do
    local ch = s:sub(i, i)
    if ch == "\n" then
      lines[#lines + 1] = cur; cur = {}
      i = i + 1
    elseif markup and (ch == "*" or ch == "_") then
      if s:sub(i + 1, i + 1) == ch then
        cur[#cur + 1] = { ch:byte(), bold and "bold" or (italic and "italic" or "normal") }
        i = i + 2
      else
        if ch == "*" then bold = not bold else italic = not italic end
        i = i + 1
      end
    else
      local c = ch:byte()
      -- utf-8 multibyte sequences decode to one codepoint (unknown -> '?')
      if c >= 0xC0 then
        local len = c >= 0xF0 and 4 or (c >= 0xE0 and 3 or 2)
        local ok, cp = pcall(utf8.codepoint, s, i)
        c = ok and cp or 63
        i = i + len - 1
      elseif c >= 0x80 then c = 63 end
      cur[#cur + 1] = { c, bold and "bold" or (italic and "italic" or "normal") }
      i = i + 1
    end
  end
  lines[#lines + 1] = cur
  return lines
end

function T.lineWidth(line)
  local w = 0
  for _, g in ipairs(line) do w = w + glyph(g[2], g[1]).a end
  return w
end

-- width of the widest line, total height
function T.size(s, base, markup, leading)
  local lines = T.layout(s, base, markup)
  local w = 0
  for _, l in ipairs(lines) do w = math.max(w, T.lineWidth(l)) end
  return w, #lines * FONT.height + (#lines - 1) * (leading or 0)
end

return T

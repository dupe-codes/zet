love.filesystem.setRequirePath(
    "?.lua;?/init.lua;"
        .. "lua_modules/share/lua/5.1/?.lua;"
        .. "lua_modules/share/lua/5.1/?/init.lua"
)

local ver = "5.1"
local ext = (jit.os == "Windows" and "dll")
    or (jit.os == "OSX" and "dylib")
    or "so"

-- Only matters during dev (unpacked folder). Inside .love this is ignored.
package.cpath = "lua_modules/lib/lua/"
    .. ver
    .. "/?."
    .. ext
    .. ";"
    .. package.cpath

local utf8 = require "utf8"

local bins = require "src.bins"
local domains = require "src.domains"
local file_utils = require "src.file-utils"
local note_writer = require "src.note_writer"

-- Registered context domains, expanded from ~/.claude/domains.json.
local DOMAINS = domains.load()
local DOMAIN_NAMES = {}
local DOMAIN_BY_NAME = {}
for _, d in ipairs(DOMAINS) do
    DOMAIN_NAMES[#DOMAIN_NAMES + 1] = d.name
    DOMAIN_BY_NAME[d.name] = d
end

-- Note-type (bin) state for the currently selected domain. Both stay empty
-- until a domain is chosen, at which point loadNoteTypes() repopulates them:
--   CATEGORY_OPTIONS - ordered tags shown in the note-type dropdown
--   NOTE_TYPE_LOOKUP - tag -> { bin, template } for saveNote()
local CATEGORY_OPTIONS = {}
local NOTE_TYPE_LOOKUP = {}

--------------------------------------------------------------
--  CONFIGURATION  -------------------------------------------
--------------------------------------------------------------
local WIN_W, WIN_H = 1440, 900 -- window size
local MARGIN = 60 -- outer margin around sheet
local TITLE_H = 50 -- title input height
local DROPDOWN_H = 44 -- dropdown height when collapsed
local OPTION_H = 38 -- height of each option row
local BTN_W, BTN_H = 120, 50 -- save button size
local SCROLL_SPEED = 40 -- pixels per wheel notch
local CONTENT_PAD = 24 -- pixels of extra space below the last line
local ARROW_W = 44 -- width reserved at the right for the arrow button
local GAP = 36 -- vertical space *between* components (was 20)
local LABEL_PAD = 4 -- gap between a label and its box

--------------------------------------------------------------
--  COLOR SCHEME   -------------------------------------------
--------------------------------------------------------------
local PAPER_COLOR = { 0.902, 0.906, 0.929 } -- #e6e7ed  (editor.bg)
local SHEET_COLOR = { 1.000, 1.000, 1.000 } -- white   (note sheet)

local BORDER_COLOR = { 0.757, 0.761, 0.780 } -- #c1c2c7 (input.border)
local FOCUS_COLOR = { 0.161, 0.349, 0.667 } -- #2959aa (focusBorder / button)

-- Buttons ----------------------------------------------------
local BTN_COLOR = { 0.161, 0.349, 0.667 } -- #2959aa (button.background)
local BTN_COL_HOVER = { 0.239, 0.447, 0.792 } -- lighter blue for hover

local CLOSE_BTN_COL = { 0.549, 0.263, 0.318 } -- #8c4351 (ansiRed)
local CLOSE_BTN_HOVER = { 0.616, 0.333, 0.376 } -- slightly lighter red

-- Dropdown / misc -------------------------------------------
local DROPDOWN_BG = { 0.902, 0.906, 0.929 } -- #e6e7ed (dropdown.bg)
local HINT_COLOR = { 0.439, 0.447, 0.502 } -- #707280 (descriptionFg)
local SCROLL_COL = { 0.565, 0.573, 0.588 } -- #909296 (scrollbar slider)
local SELECT_BG = { 0.698, 0.776, 0.925, 0.9 } -- pale blue for list highlight

-- arrow-strip greys (for dropdown button)
local ARROW_BG = { 0.922, 0.925, 0.937 } -- #ebecf0 (inactive)
local ARROW_BG_HOVER = { 0.847, 0.855, 0.878 } -- #d8dae0 (hover)

local titleFont, subtitleFont -- declare up top
local HEADER_H = 90 -- vertical space we’ll reserve

--------------------------------------------------------------
--  GLOBAL STATE  --------------------------------------------
--------------------------------------------------------------
local sheet, titleBox, dropdown, domainDropdown, descBox, noteBox
local saveBtn, closeBtn, tagsBox
local font, hintFont
local titleText, noteText = "", ""
local descriptionText = ""
local tagsText = "" -- comma-separated manual tags
local hoverSave = false
local hoverClose = false
local noteScroll = 0 -- current vertical scroll offset
local caretPos = 1 -- UTF‑8 char index where next insert happens (1‑based)

local selStart, selEnd = nil, nil -- UTF‑8 char indices (inclusive range)

local FIELDS = {} -- ordered list of focusable elements
local focusIndex = 1 -- 1-based; titleBox gets focus first

local function setFocus(i)
    focusIndex = ((i - 1) % #FIELDS) + 1 -- wrap around
    -- clear everything, then mark the chosen one active
    for _, box in ipairs(FIELDS) do
        box.active = false
    end
    FIELDS[focusIndex].active = true
end

local function hasSelection()
    return selStart and selEnd and selStart ~= selEnd
end
local function clearSel()
    selStart, selEnd = nil, nil
end

-- Normalise so selStart < selEnd
local function normalisedSel()
    if not hasSelection() then
        return nil
    end
    return math.min(selStart, selEnd), math.max(selStart, selEnd)
end

local function insertAt(s, insert, pos)
    local byte = utf8.offset(s, pos)
    if not byte then
        return s .. insert, pos + utf8.len(insert)
    end
    return s:sub(1, byte - 1) .. insert .. s:sub(byte), pos + utf8.len(insert)
end

local function replaceSelection(s, new)
    if not hasSelection() then
        return insertAt(s, new, caretPos)
    end
    local a, b = normalisedSel()
    local byteA = utf8.offset(s, a)
    local byteB = utf8.offset(s, b + 1) or (#s + 1)
    local out = s:sub(1, byteA - 1) .. new .. s:sub(byteB)
    caretPos = a + utf8.len(new)
    clearSel()
    return out, caretPos
end

local function contains(r, x, y)
    return x > r.x and x < r.x + r.w and y > r.y and y < r.y + r.h
end

local function backspaceAt(s, pos)
    if pos <= 1 then
        return s, pos
    end
    local bPrev = utf8.offset(s, pos - 1)
    local bCur = utf8.offset(s, pos)
    return s:sub(1, bPrev - 1) .. s:sub(bCur), pos - 1
end

local function pasteClipboard()
    local clip = love.system.getClipboardText() or ""
    if clip == "" then
        return
    end

    if titleBox.active then
        titleText = titleText .. clip
    elseif descBox.active then
        descriptionText = descriptionText .. clip
    elseif tagsBox.active then
        tagsText = tagsText .. clip
    elseif noteBox.active then
        noteText, caretPos = replaceSelection(noteText, clip)
    end
end

local function getActiveText()
    if titleBox.active then
        return titleText, "title"
    elseif descBox.active then
        return descriptionText, "desc"
    elseif tagsBox.active then
        return tagsText, "tags"
    elseif noteBox.active then
        return noteText, "note"
    end
end

-- return byte‑range (inclusive) of the current selection in `s`
local function selectedBytes(s)
    local a, b = normalisedSel() -- UTF‑8 indices
    if not a then
        return nil
    end
    local byteA = utf8.offset(s, a)
    local byteB = (utf8.offset(s, b + 1) or (#s + 1)) - 1
    return byteA, byteB -- inclusive bytes
end

local function copySelection()
    if not hasSelection() then
        local txt, _ = getActiveText()
        if txt then
            love.system.setClipboardText(txt)
        end
        return
    end
    local byteA, byteB = selectedBytes(noteText)
    love.system.setClipboardText(noteText:sub(byteA, byteB))
end

local function cutSelection()
    local buf
    local setBuf

    if noteBox.active then
        buf = noteText
        setBuf = function(new, newCaret)
            noteText, caretPos = new, newCaret or 1
        end
    elseif titleBox.active then
        buf = titleText
        setBuf = function(new)
            titleText = new
        end
    elseif descBox.active then
        buf = descriptionText
        setBuf = function(new)
            descriptionText = new
        end
    elseif tagsBox.active then
        buf = tagsText
        setBuf = function(new)
            tagsText = new
        end
    else
        return -- nothing focused
    end

    local byteA, byteB = selectedBytes(buf)

    if not byteA then -- ►  NO HIGHLIGHT  ◄
        -- treat the whole field as selected
        love.system.setClipboardText(buf)
        setBuf("", 1)
        clearSel()
        return
    end

    love.system.setClipboardText(buf:sub(byteA, byteB)) -- copy
    local new = buf:sub(1, byteA - 1) .. buf:sub(byteB + 1) -- delete
    setBuf(new, utf8.len(new) + 1) -- caret at end
    clearSel()
end

local function deleteSelection()
    if not noteBox.active then
        return
    end

    local byteA, byteB = selectedBytes(noteText)
    if not byteA then
        return
    end -- nothing highlighted

    noteText = noteText:sub(1, byteA - 1) -- drop selection
        .. noteText:sub(byteB + 1)

    caretPos = byteA -- caret goes to start
    clearSel()
end

-- wrapped lines helper
local function getWrappedLines(text, wrapW, f)
    local _, lines = f:getWrap(text, wrapW)
    return lines
end

local function getContentHeight(text, wrapW, f)
    return #getWrappedLines(text, wrapW, f) * f:getHeight() + CONTENT_PAD
end

-- calculate caret x,y inside noteBox (before scroll)
local function getCaretXY(text, pos, wrapW, f)
    local byte = utf8.offset(text, pos)
    local textToCaret = byte and text:sub(1, byte - 1) or text
    local lines = getWrappedLines(textToCaret, wrapW, f)
    local lineIdx = #lines
    local lineText = lines[lineIdx] or ""
    local x = f:getWidth(lineText)
    local y = (lineIdx - 1) * f:getHeight()
    return x, y
end

local function parseTags(s)
    local out, seen = {}, {}
    for part in (s or ""):gmatch "[^,]+" do
        local t = part:gsub("^%s+", ""):gsub("%s+$", "")
        if t ~= "" and not seen[t] then
            seen[t] = true
            table.insert(out, t)
        end
    end
    return out
end

local function utf8_backspace(s)
    local len = utf8.len(s or "")
    if not len or len == 0 then
        return ""
    end
    local b = utf8.offset(s, len)
    return s:sub(1, b - 1)
end

-- Rebuild `dd.filtered` from `options`, honouring the current search query.
-- Shared by both the domain and note-type dropdowns.
local function updateDropdownFilter(dd, options)
    local q = (dd.search or ""):lower()
    dd.filtered = {}
    if q == "" then
        for _, v in ipairs(options) do
            table.insert(dd.filtered, v)
        end
    else
        for _, v in ipairs(options) do
            if v:lower():find(q, 1, true) then
                table.insert(dd.filtered, v)
            end
        end
    end
    if #dd.filtered == 0 then
        dd.highlight = 0
    else
        dd.highlight = math.min(dd.highlight or 1, #dd.filtered)
        if dd.highlight < 1 then
            dd.highlight = 1
        end
    end
end

-- Populate the note-type dropdown from the chosen domain's resolved bins.
local function loadNoteTypes(domain)
    CATEGORY_OPTIONS = {}
    NOTE_TYPE_LOOKUP = {}
    for _, nt in ipairs(bins.resolve(domain.path)) do
        table.insert(CATEGORY_OPTIONS, nt.tag)
        NOTE_TYPE_LOOKUP[nt.tag] = { bin = nt.bin, template = nt.template }
    end
    dropdown.selected = CATEGORY_OPTIONS[1]
    dropdown.search = ""
    dropdown.highlight = 1
    updateDropdownFilter(dropdown, CATEGORY_OPTIONS)
end

-- Select a domain by name and refresh the note-type dropdown for it.
local function selectDomain(name)
    domainDropdown.selected = name
    local domain = DOMAIN_BY_NAME[name]
    if domain then
        loadNoteTypes(domain)
    end
end

-- Return the dropdown that currently has focus, its option list, and a
-- callback to apply a selection. Used by the shared keyboard/text handlers.
local function activeDropdown()
    if domainDropdown and domainDropdown.active then
        return domainDropdown, DOMAIN_NAMES, selectDomain
    end
    if dropdown and dropdown.active then
        return dropdown,
            CATEGORY_OPTIONS,
            function(v)
                dropdown.selected = v
            end
    end
    return nil
end

local function saveNote()
    local domain = domainDropdown.selected
        and DOMAIN_BY_NAME[domainDropdown.selected]
    if not domain then
        love.window.showMessageBox(
            "zet – error",
            "Pick a domain before saving.",
            "error",
            true
        )
        return
    end

    local nt = dropdown.selected and NOTE_TYPE_LOOKUP[dropdown.selected]
    if not nt then
        love.window.showMessageBox(
            "zet – error",
            "Pick a note type before saving.",
            "error",
            true
        )
        return
    end

    local destDir = domain.path .. "/" .. nt.bin
    local templatePath = domain.path .. "/" .. nt.template

    local title = titleText:gsub("^%s+", ""):gsub("%s+$", "")
    local baseName = title ~= "" and title or os.date "%Y-%m-%d_%H%M%S"
    local fullPath = destDir .. "/" .. baseName .. ".md"

    local tags = parseTags(tagsText)
    local ok_render, rendered_note = pcall(note_writer.render, templatePath, {
        description = descriptionText,
        tags = tags,
        content = noteText,
    })
    if not ok_render then
        love.window.showMessageBox(
            "zet – error",
            ("Failed to render note:\n%s"):format(tostring(rendered_note)),
            "error",
            true
        )
        return
    end

    local ok, err = file_utils.write_file(fullPath, rendered_note)
    if not ok then
        local msg
        if err == "exists" then
            msg = (
                'A note named "%s" already exists in:\n%s\n\n'
                .. "Please choose a different title."
            ):format(baseName, destDir)
        else
            msg = ("Failed to save note:\n%s"):format(err)
        end

        love.window.showMessageBox("zet – error", msg, "error", true)
        return
    end

    love.window.showMessageBox(
        "zet – saved",
        ("Wrote %s"):format(fullPath),
        "info",
        true
    )
    love.event.quit()
end

--------------------------------------------------------------
--  LOVE CALLBACKS  ------------------------------------------
--------------------------------------------------------------
function love.load()
    titleFont = love.graphics.newFont(32)
    subtitleFont = love.graphics.newFont(18)

    love.window.setMode(WIN_W, WIN_H, { centered = true, resizable = false })
    love.window.setTitle "zet"
    love.graphics.setBackgroundColor(PAPER_COLOR)
    love.keyboard.setKeyRepeat(true)

    font = love.graphics.newFont(24)
    hintFont = love.graphics.newFont(16)
    love.graphics.setFont(font)

    sheet = {
        x = MARGIN,
        y = MARGIN,
        w = WIN_W - MARGIN * 2,
        h = WIN_H - MARGIN * 2,
    }

    -- ── Title
    titleBox = {
        x = sheet.x + 40,
        y = sheet.y + HEADER_H + GAP / 2,
        w = sheet.w - 80,
        h = TITLE_H,
        active = false,
    }

    -- ── Domain dropdown (which vault to write into)
    domainDropdown = {
        x = titleBox.x,
        y = titleBox.y + TITLE_H + GAP,
        w = titleBox.w,
        h = DROPDOWN_H,
        expanded = false,
        active = false,
        selected = nil, -- no domain chosen yet
        search = "",
        filtered = {},
        highlight = 1,
    }
    updateDropdownFilter(domainDropdown, DOMAIN_NAMES)

    -- ── Note-type dropdown (empty until a domain is picked)
    dropdown = {
        x = domainDropdown.x,
        y = domainDropdown.y + DROPDOWN_H + GAP,
        w = domainDropdown.w,
        h = DROPDOWN_H,
        expanded = false,
        active = false,
        selected = CATEGORY_OPTIONS[1],
        search = "",
        filtered = {},
        highlight = 1,
    }
    updateDropdownFilter(dropdown, CATEGORY_OPTIONS)

    -- ── Description (single-line)
    descBox = {
        x = dropdown.x,
        y = dropdown.y + DROPDOWN_H + GAP,
        w = dropdown.w,
        h = TITLE_H,
        active = false,
    }

    -- ── Additional Tags (comma-separated)
    tagsBox = {
        x = descBox.x,
        y = descBox.y + TITLE_H + GAP,
        w = descBox.w,
        h = TITLE_H,
        active = false,
    }

    local btnTop = sheet.y + sheet.h - BTN_H - 40
    local noteTop = tagsBox.y + TITLE_H + 20
    noteBox = {
        x = tagsBox.x,
        y = noteTop + GAP,
        w = tagsBox.w,
        h = btnTop - noteTop - GAP,
        active = false,
    }

    saveBtn = {
        x = sheet.x + sheet.w - BTN_W - 40,
        y = sheet.y + sheet.h - BTN_H - 40 + GAP / 2,
        w = BTN_W,
        h = BTN_H,
    }

    closeBtn = {
        x = saveBtn.x - BTN_W - 20,
        y = saveBtn.y,
        w = BTN_W,
        h = BTN_H,
    }
    caretPos = 1

    FIELDS = { domainDropdown, dropdown, titleBox, descBox, tagsBox, noteBox }
    setFocus(1) -- domainDropdown starts active
end

function love.update(dt)
    local mx, my = love.mouse.getPosition()
    hoverSave = contains(saveBtn, mx, my)
    hoverClose = contains(closeBtn, mx, my)
end

function love.textinput(t)
    local dd, opts = activeDropdown()
    if dd then
        dd.search = (dd.search or "") .. t
        updateDropdownFilter(dd, opts)
        dd.expanded = true
        return
    end

    if titleBox.active then
        titleText = titleText .. t
    elseif descBox.active then
        descriptionText = descriptionText .. t
    elseif tagsBox.active then
        tagsText = tagsText .. t
    elseif noteBox.active then
        noteText, caretPos = replaceSelection(noteText, t)
    end
end

function love.keypressed(key)
    if key == "backspace" then
        local dd, opts = activeDropdown()
        if dd then
            dd.search = utf8_backspace(dd.search)
            updateDropdownFilter(dd, opts)
            return
        end

        if noteBox.active and selectedBytes(noteText) then
            deleteSelection()
            return
        end

        if titleBox.active then
            titleText = backspaceAt(titleText, utf8.len(titleText) + 1)
        elseif descBox.active then
            descriptionText =
                backspaceAt(descriptionText, utf8.len(descriptionText) + 1)
        elseif tagsBox.active then
            tagsText = backspaceAt(tagsText, utf8.len(tagsText) + 1)
        elseif noteBox.active then
            noteText, caretPos = backspaceAt(noteText, caretPos)
        end
        return
    end

    if key == "escape" then
        love.event.quit()
        return
    end

    if key == "tab" then
        local step = love.keyboard.isDown("lshift", "rshift") and -1 or 1
        setFocus(focusIndex + step)
        -- special-case: put caret at end when we enter the note field
        if noteBox.active then
            caretPos = utf8.len(noteText) + 1
        end
        -- collapse dropdowns if they had been expanded
        dropdown.expanded = false
        domainDropdown.expanded = false
        return
    end

    if key == "return" and noteBox.active then
        if love.keyboard.isDown "lshift" or love.keyboard.isDown "rshift" then
            saveNote()
        else
            noteText, caretPos = insertAt(noteText, "\n", caretPos)
        end
        return
    end

    local ctrl = love.keyboard.isDown("lctrl", "rctrl")
    if key == "v" and ctrl then
        pasteClipboard()
        return
    end

    if key == "c" and ctrl then
        copySelection()
        return
    end
    if key == "x" and ctrl then
        cutSelection()
        return
    end

    -- Dropdown navigation (works for whichever dropdown has focus)
    local navDd, navOpts, navSelect = activeDropdown()
    if navDd then
        if key == "down" then
            if navDd.expanded and #navDd.filtered > 0 then
                navDd.highlight = math.min(navDd.highlight + 1, #navDd.filtered)
            else
                navDd.expanded = true
            end
            return
        elseif key == "up" then
            if navDd.expanded and #navDd.filtered > 0 then
                navDd.highlight = math.max(navDd.highlight - 1, 1)
            end
            return
        elseif key == "return" then
            if
                navDd.expanded
                and #navDd.filtered > 0
                and navDd.highlight > 0
            then
                navSelect(navDd.filtered[navDd.highlight])
            end
            navDd.expanded = false
            navDd.search = ""
            updateDropdownFilter(navDd, navOpts)
            return
        elseif key == "escape" then
            navDd.expanded = false
            navDd.search = ""
            updateDropdownFilter(navDd, navOpts)
            return
        end
    end

    local shift = love.keyboard.isDown("lshift", "rshift")
    if key == "left" and noteBox.active then
        caretPos = math.max(1, caretPos - 1)
        if shift then
            selEnd = selEnd and caretPos or caretPos
            selStart = selStart or caretPos + 1
        else
            clearSel()
        end
        return
    elseif key == "right" and noteBox.active then
        caretPos = math.min(utf8.len(noteText) + 1, caretPos + 1)
        if shift then
            selEnd = selEnd and caretPos or caretPos
            selStart = selStart or caretPos - 1
        else
            clearSel()
        end
        return
    end

    if (key == "c" or key == "x") and (love.keyboard.isDown "lctrl") then
        if key == "c" then
            copySelection()
        else
            cutSelection()
        end
        return
    end
end

function love.wheelmoved(dx, dy)
    local mx, my = love.mouse.getPosition()
    if noteBox.active or contains(noteBox, mx, my) then
        local contentH = getContentHeight(noteText, noteBox.w - 24, font)
        if contentH > noteBox.h then
            noteScroll = noteScroll + -dy * SCROLL_SPEED
            local maxScroll = contentH - noteBox.h
            if noteScroll < 0 then
                noteScroll = 0
            end
            if noteScroll > maxScroll then
                noteScroll = maxScroll
            end
        end
    end
end

-- Collapse a dropdown when a click lands outside both its field and its
-- expanded options panel.
local function collapseOutside(dd, options, x, y)
    if dd.expanded and not contains(dd, x, y) then
        local opts = {
            x = dd.x,
            y = dd.y + dd.h,
            w = dd.w,
            h = #options * OPTION_H,
        }
        if not contains(opts, x, y) then
            dd.expanded = false
        end
    end
end

-- map click in noteBox to caret position
local function setCaretFromClick(x, y)
    local relX = x - (noteBox.x + 12)
    local relY = y - (noteBox.y + 12) + noteScroll
    if relX < 0 then
        relX = 0
    end
    if relY < 0 then
        relY = 0
    end
    local lines = getWrappedLines(noteText, noteBox.w - 24, font)
    local lineH = font:getHeight()
    local lineIdx = math.floor(relY / lineH) + 1
    if lineIdx > #lines then
        lineIdx = #lines
    end
    if lineIdx < 1 then
        lineIdx = 1
    end
    local charOffsetInText = 0
    for i = 1, lineIdx - 1 do
        charOffsetInText = charOffsetInText + utf8.len(lines[i]) + 1
    end -- +1 for newline
    local line = lines[lineIdx]
    -- iterate char by char to find click pos within line
    local accW = 0
    local charInLine = 1
    for _, c in utf8.codes(line) do
        local ch = utf8.char(c)
        local w = font:getWidth(ch)
        if accW + w / 2 >= relX then
            break
        end
        accW = accW + w
        charInLine = charInLine + 1
    end
    caretPos = charOffsetInText + charInLine
end

function love.mousepressed(x, y, btn)
    if btn ~= 1 then
        return
    end

    -- domain dropdown
    if contains(domainDropdown, x, y) then
        setFocus(1)
        domainDropdown.expanded = not domainDropdown.expanded
        dropdown.expanded = false
        return
    end
    if domainDropdown.expanded then
        local panel = {
            x = domainDropdown.x,
            y = domainDropdown.y + domainDropdown.h,
            w = domainDropdown.w,
            h = #domainDropdown.filtered * OPTION_H,
        }
        if contains(panel, x, y) then
            local i = math.floor((y - panel.y) / OPTION_H) + 1
            if i >= 1 and i <= #domainDropdown.filtered then
                selectDomain(domainDropdown.filtered[i])
            end
            domainDropdown.expanded = false
            domainDropdown.search = ""
            updateDropdownFilter(domainDropdown, DOMAIN_NAMES)
            return -- consume click; panel overlaps the field beneath it
        end
        domainDropdown.expanded = false
        domainDropdown.search = ""
        updateDropdownFilter(domainDropdown, DOMAIN_NAMES)
    end

    -- note-type dropdown
    if contains(dropdown, x, y) then
        setFocus(2)
        dropdown.expanded = not dropdown.expanded
        domainDropdown.expanded = false
        return
    end
    if dropdown.expanded then
        local panel = {
            x = dropdown.x,
            y = dropdown.y + dropdown.h,
            w = dropdown.w,
            h = #dropdown.filtered * OPTION_H,
        }
        if contains(panel, x, y) then
            local i = math.floor((y - panel.y) / OPTION_H) + 1
            if i >= 1 and i <= #dropdown.filtered then
                dropdown.selected = dropdown.filtered[i]
            end
            dropdown.expanded = false
            dropdown.search = ""
            updateDropdownFilter(dropdown, CATEGORY_OPTIONS)
            return -- consume click; panel overlaps the field beneath it
        end
        dropdown.expanded = false
        dropdown.search = ""
        updateDropdownFilter(dropdown, CATEGORY_OPTIONS)
    end

    collapseOutside(domainDropdown, DOMAIN_NAMES, x, y)
    collapseOutside(dropdown, CATEGORY_OPTIONS, x, y)

    -- activate text boxes
    titleBox.active = contains(titleBox, x, y)
    descBox.active = contains(descBox, x, y)
    tagsBox.active = contains(tagsBox, x, y)
    noteBox.active = contains(noteBox, x, y)

    if titleBox.active then
        setFocus(3)
    elseif descBox.active then
        setFocus(4)
    elseif tagsBox.active then
        setFocus(5)
    elseif noteBox.active then
        setFocus(6)
    end

    if noteBox.active then
        setCaretFromClick(x, y)
    end

    if contains(saveBtn, x, y) then
        saveNote()
        return
    end

    if contains(closeBtn, x, y) then
        love.event.quit()
        return
    end

    if noteBox.active then
        setCaretFromClick(x, y)
        selStart, selEnd = caretPos, caretPos -- start a zero‑width sel
    else
        clearSel()
    end
end

function love.mousemoved(x, y, dx, dy)
    if domainDropdown.expanded then
        local i = math.floor(
            (y - (domainDropdown.y + domainDropdown.h)) / OPTION_H
        ) + 1
        if i >= 1 and i <= #domainDropdown.filtered then
            domainDropdown.highlight = i
        end
    end
    if dropdown.expanded then
        local i = math.floor((y - (dropdown.y + dropdown.h)) / OPTION_H) + 1
        if i >= 1 and i <= #dropdown.filtered then
            dropdown.highlight = i
        end
    end
    if noteBox.active and love.mouse.isDown(1) then
        setCaretFromClick(x, y)
        selEnd = caretPos -- live‑update drag
    end
end

--------------------------------------------------------------
--  DRAW HELPERS  -------------------------------------------
--------------------------------------------------------------
local function drawInput(box)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", box.x, box.y, box.w, box.h, 8, 8)
    love.graphics.setColor(box.active and FOCUS_COLOR or BORDER_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", box.x, box.y, box.w, box.h, 8, 8)
end

-- Draw a dropdown (field, arrow, and expanded options panel). `dropdown` here
-- is the local parameter, so the same routine renders both dropdowns.
local function drawDropdown(dropdown)
    -- Base field
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle(
        "fill",
        dropdown.x,
        dropdown.y,
        dropdown.w,
        dropdown.h,
        8,
        8
    )

    -- Outline
    love.graphics.setColor(dropdown.active and FOCUS_COLOR or BORDER_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle(
        "line",
        dropdown.x,
        dropdown.y,
        dropdown.w,
        dropdown.h,
        8,
        8
    )

    -- Field text: show search if any, else selected
    local fieldText = (dropdown.search ~= "" and dropdown.search)
        or dropdown.selected
        or ""
    love.graphics.setColor(0, 0, 0)
    love.graphics.printf(
        fieldText,
        dropdown.x + 12,
        dropdown.y + 10,
        dropdown.w - ARROW_W - 12,
        "left"
    )

    -- Arrow button
    local arrowX = dropdown.x + dropdown.w - ARROW_W
    local hover = contains(
        { x = arrowX, y = dropdown.y, w = ARROW_W, h = dropdown.h },
        love.mouse.getPosition()
    )

    love.graphics.setColor(hover and ARROW_BG_HOVER or ARROW_BG)
    love.graphics.rectangle(
        "fill",
        arrowX,
        dropdown.y,
        ARROW_W,
        dropdown.h,
        8,
        8
    )

    love.graphics.setColor(BORDER_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.line(
        arrowX,
        dropdown.y + 4,
        arrowX,
        dropdown.y + dropdown.h - 4
    )

    local midX = arrowX + ARROW_W / 2
    local midY = dropdown.y + dropdown.h / 2
    love.graphics.setColor(0.2, 0.2, 0.2)
    if dropdown.expanded then
        love.graphics.polygon(
            "fill",
            midX - 6,
            midY + 3,
            midX + 6,
            midY + 3,
            midX,
            midY - 4
        )
    else
        love.graphics.polygon(
            "fill",
            midX - 6,
            midY - 3,
            midX + 6,
            midY - 3,
            midX,
            midY + 4
        )
    end

    -- Options panel
    if dropdown.expanded then
        local listH = math.max(1, #dropdown.filtered) * OPTION_H

        love.graphics.setColor(DROPDOWN_BG)
        love.graphics.rectangle(
            "fill",
            dropdown.x,
            dropdown.y + dropdown.h,
            dropdown.w,
            listH,
            8,
            8
        )
        love.graphics.setColor(BORDER_COLOR)
        love.graphics.rectangle(
            "line",
            dropdown.x,
            dropdown.y + dropdown.h,
            dropdown.w,
            listH,
            8,
            8
        )

        for i, opt in ipairs(dropdown.filtered) do
            local oy = dropdown.y + dropdown.h + (i - 1) * OPTION_H
            if i == dropdown.highlight then
                love.graphics.setColor(SELECT_BG)
                love.graphics.rectangle(
                    "fill",
                    dropdown.x + 1.5,
                    oy,
                    dropdown.w - 3,
                    OPTION_H
                )
                love.graphics.setColor(0, 0, 0)
            else
                love.graphics.setColor(0, 0, 0)
            end
            love.graphics.printf(
                opt,
                dropdown.x + 12,
                oy + 8,
                dropdown.w - 24,
                "left"
            )
        end

        if #dropdown.filtered == 0 then
            local oy = dropdown.y + dropdown.h
            love.graphics.setColor(0.4, 0.4, 0.4)
            love.graphics.printf(
                "(no matches)",
                dropdown.x + 12,
                oy + 8,
                dropdown.w - 24,
                "left"
            )
        end
    end
end

local function drawNoteBox()
    drawInput(noteBox)
    love.graphics.setScissor(
        noteBox.x + 3,
        noteBox.y + 3,
        noteBox.w - 6,
        noteBox.h - 6
    )
    love.graphics.push()
    love.graphics.translate(0, -noteScroll)
    love.graphics.setColor(0, 0, 0)

    -- draw blue highlight behind selected range
    if hasSelection() then
        local a, b = normalisedSel()
        local wrapW = noteBox.w - 24
        local lines = getWrappedLines(noteText, wrapW, font)

        -- Walk every char and emit rectangles where index ∈ [a,b]
        local idx = 1
        local y = noteBox.y + 12
        for _, line in ipairs(lines) do
            local lineLen = utf8.len(line)
            local lineStart = idx
            local lineEnd = idx + lineLen - 1

            local selLo = math.max(a, lineStart)
            local selHi = math.min(b, lineEnd)

            if selLo <= selHi then
                local pre = line:sub(1, selLo - lineStart)
                local mid =
                    line:sub(selLo - lineStart + 1, selHi - lineStart + 1)
                local x1 = noteBox.x + 12 + font:getWidth(pre)
                local wSel = font:getWidth(mid)
                love.graphics.setColor(0.698, 0.776, 0.925, 0.6) -- pale blue
                love.graphics.rectangle("fill", x1, y, wSel, font:getHeight())
            end
            idx = idx + lineLen + 1 -- +1 for newline
            y = y + font:getHeight()
        end
        love.graphics.setColor(0, 0, 0) -- reset
    end

    love.graphics.printf(
        noteText,
        noteBox.x + 12,
        noteBox.y + 12,
        noteBox.w - 24,
        "left"
    )

    if noteBox.active then
        local cx, cy = getCaretXY(noteText, caretPos, noteBox.w - 24, font)
        local caretX = noteBox.x + 12 + cx -- 12-px left padding
        local caretY = noteBox.y + 12 + cy -- 12-px top padding
        love.graphics.setColor(0, 0, 0)
        love.graphics.rectangle("fill", caretX, caretY, 2, font:getHeight())
    end

    love.graphics.pop()
    love.graphics.setScissor()

    -- scrollbar
    local contentH = getContentHeight(noteText, noteBox.w - 24, font)
    if contentH > noteBox.h then
        local ratio = noteBox.h / contentH
        local barH = noteBox.h * ratio
        local maxScroll = contentH - noteBox.h
        local barY = noteBox.y + (noteScroll / maxScroll) * (noteBox.h - barH)
        love.graphics.setColor(SCROLL_COL)
        love.graphics.rectangle(
            "fill",
            noteBox.x + noteBox.w - 6,
            barY,
            4,
            barH,
            2,
            2
        )
    end

    -- hint
    love.graphics.setFont(hintFont)
    love.graphics.setColor(HINT_COLOR)
    local hintY = noteBox.y + noteBox.h - hintFont:getHeight() - 6
    love.graphics.printf(
        "shift + enter to save",
        noteBox.x + 12,
        hintY,
        noteBox.w - 24,
        "right"
    )
    love.graphics.setFont(font)
end

local function label(text, box)
    love.graphics.setFont(hintFont)
    love.graphics.setColor(HINT_COLOR)
    love.graphics.print(text, box.x, box.y - hintFont:getHeight() - LABEL_PAD)
    love.graphics.setFont(font)
end

function love.draw()
    love.graphics.setColor(0, 0, 0, 0.09)
    love.graphics.rectangle(
        "fill",
        sheet.x + 4,
        sheet.y + 4,
        sheet.w,
        sheet.h,
        12,
        12
    )
    love.graphics.setColor(SHEET_COLOR)
    love.graphics.rectangle("fill", sheet.x, sheet.y, sheet.w, sheet.h, 12, 12)

    love.graphics.setFont(titleFont)
    love.graphics.setColor(FOCUS_COLOR) -- same blue you use for focus
    love.graphics.print("zet", sheet.x + 40, sheet.y + 10)

    love.graphics.setFont(subtitleFont)
    love.graphics.setColor(HINT_COLOR) -- subtle grey
    love.graphics.print(
        "the giga zettelkasten helper",
        sheet.x + 40,
        sheet.y + 10 + titleFont:getHeight()
    )

    love.graphics.setFont(font)

    label("Title", titleBox)
    label("Domain", domainDropdown)
    label("Note type", dropdown)
    label("Description", descBox)
    label("Tags", tagsBox)
    label("Note", noteBox)

    drawInput(titleBox)

    love.graphics.setColor(0, 0, 0)
    love.graphics.printf(
        titleText,
        titleBox.x + 12,
        titleBox.y + 12,
        titleBox.w - 24,
        "left"
    )

    drawInput(descBox)
    love.graphics.setColor(0, 0, 0)
    love.graphics.printf(
        descriptionText,
        descBox.x + 12,
        descBox.y + 12,
        descBox.w - 24,
        "left"
    )

    drawInput(tagsBox)
    love.graphics.setColor(0, 0, 0)
    love.graphics.printf(
        tagsText,
        tagsBox.x + 12,
        tagsBox.y + 12,
        tagsBox.w - 24,
        "left"
    )

    drawNoteBox()
    -- Note-type first, then domain, so the upper domain panel layers on top.
    drawDropdown(dropdown)
    drawDropdown(domainDropdown)

    love.graphics.setColor(hoverSave and BTN_COL_HOVER or BTN_COLOR)
    love.graphics.rectangle(
        "fill",
        saveBtn.x,
        saveBtn.y,
        saveBtn.w,
        saveBtn.h,
        6,
        6
    )
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Save", saveBtn.x, saveBtn.y + 14, saveBtn.w, "center")

    love.graphics.setColor(hoverClose and CLOSE_BTN_HOVER or CLOSE_BTN_COL)
    love.graphics.rectangle(
        "fill",
        closeBtn.x,
        closeBtn.y,
        closeBtn.w,
        closeBtn.h,
        6,
        6
    )
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(
        "Close",
        closeBtn.x,
        closeBtn.y + 14,
        closeBtn.w,
        "center"
    )
end

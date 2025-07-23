-- main.lua  •  LÖVE 11.5+
-- Notes UI with dropdown, Shift+Enter save, scrollable note box & scrollbar.
-- NEW: click‑to‑place caret inside the note field, and editing occurs at caret.

local utf8 = require "utf8"

--------------------------------------------------------------
--  CONFIGURATION  -------------------------------------------
--------------------------------------------------------------
local WIN_W, WIN_H = 900, 650 -- window size
local MARGIN = 60 -- outer margin around sheet
local TITLE_H = 50 -- title input height
local DROPDOWN_H = 44 -- dropdown height when collapsed
local OPTION_H = 38 -- height of each option row
local BTN_W, BTN_H = 120, 50 -- save button size
local SCROLL_SPEED = 40 -- pixels per wheel notch
local CONTENT_PAD = 24 -- pixels of extra space below the last line
local ARROW_W = 44 -- width reserved at the right for the arrow button

-- Colours
local PAPER_COLOR = { 0.976, 0.973, 0.949 }
local SHEET_COLOR = { 1, 1, 1 }
local BORDER_COLOR = { 0.82, 0.82, 0.82 }
local FOCUS_COLOR = { 0.25, 0.55, 0.95 }
local BTN_COLOR = { 0.23, 0.49, 0.95 }
local BTN_COL_HOVER = { 0.28, 0.55, 1.00 }
local DROPDOWN_BG = { 0.97, 0.97, 0.97 }
local HINT_COLOR = { 0.45, 0.45, 0.45 }
local SCROLL_COL = { 0.75, 0.75, 0.75 }

-- Category list — extend here 👇
local CATEGORY_OPTIONS = { "art", "hacking", "gamedev" }

--------------------------------------------------------------
--  GLOBAL STATE  --------------------------------------------
--------------------------------------------------------------
local sheet, titleBox, dropdown, noteBox, saveBtn
local font, hintFont
local titleText, noteText = "", ""
local hoverBtn = false
local noteScroll = 0 -- current vertical scroll offset
local caretPos = 1 -- UTF‑8 char index where next insert happens (1‑based)

--------------------------------------------------------------
--  HELPER FUNCTIONS  ----------------------------------------
--------------------------------------------------------------
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

local function insertAt(s, insert, pos)
    local byte = utf8.offset(s, pos)
    if not byte then
        return s .. insert, pos + utf8.len(insert)
    end
    return s:sub(1, byte - 1) .. insert .. s:sub(byte), pos + utf8.len(insert)
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

local function saveNote()
    local msg = ("Category: %s\nTitle: %s\n\nNote:\n%s"):format(
        dropdown.selected,
        titleText,
        noteText
    )
    love.window.showMessageBox("zet", msg, "info", true)
end

--------------------------------------------------------------
--  LOVE CALLBACKS  ------------------------------------------
--------------------------------------------------------------
function love.load()
    love.window.setMode(WIN_W, WIN_H, { centered = true, resizable = false })
    love.window.setTitle "zet"
    love.graphics.setBackgroundColor(PAPER_COLOR)
    love.keyboard.setKeyRepeat(true)

    font = love.graphics.newFont(24)
    hintFont = love.graphics.newFont(16)
    love.graphics.setFont(font)

    -- Layout
    sheet = {
        x = MARGIN,
        y = MARGIN,
        w = WIN_W - MARGIN * 2,
        h = WIN_H - MARGIN * 2,
    }
    titleBox = {
        x = sheet.x + 40,
        y = sheet.y + 40,
        w = sheet.w - 80,
        h = TITLE_H,
        active = false,
    }
    dropdown = {
        x = titleBox.x,
        y = titleBox.y + TITLE_H + 20,
        w = titleBox.w,
        h = DROPDOWN_H,
        expanded = false,
        selected = CATEGORY_OPTIONS[1],
    }
    noteBox = {
        x = dropdown.x,
        y = dropdown.y + DROPDOWN_H + 20,
        w = dropdown.w,
        h = sheet.h - TITLE_H - DROPDOWN_H - BTN_H - 140,
        active = false,
    }
    saveBtn = {
        x = sheet.x + sheet.w - BTN_W - 40,
        y = sheet.y + sheet.h - BTN_H - 40,
        w = BTN_W,
        h = BTN_H,
    }
    caretPos = 1
end

function love.update(dt)
    local mx, my = love.mouse.getPosition()
    hoverBtn = contains(saveBtn, mx, my)
end

function love.textinput(t)
    if titleBox.active then
        titleText = titleText .. t
    elseif noteBox.active then
        noteText, caretPos = insertAt(noteText, t, caretPos)
    end
end

function love.keypressed(key)
    if key == "backspace" then
        if titleBox.active then
            titleText = backspaceAt(titleText, utf8.len(titleText) + 1)
        elseif noteBox.active then
            noteText, caretPos = backspaceAt(noteText, caretPos)
        end
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

-- Collapse dropdown helper
local function collapseOutside(x, y)
    if dropdown.expanded and not contains(dropdown, x, y) then
        local opts = {
            x = dropdown.x,
            y = dropdown.y + dropdown.h,
            w = dropdown.w,
            h = #CATEGORY_OPTIONS * OPTION_H,
        }
        if not contains(opts, x, y) then
            dropdown.expanded = false
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
    for i, c in utf8.codes(line) do
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
    -- dropdown
    if contains(dropdown, x, y) then
        dropdown.expanded = not dropdown.expanded
        titleBox.active, noteBox.active = false, false
        return
    end
    if dropdown.expanded then
        local i = math.floor((y - (dropdown.y + dropdown.h)) / OPTION_H) + 1
        if i >= 1 and i <= #CATEGORY_OPTIONS then
            dropdown.selected = CATEGORY_OPTIONS[i]
        end
        dropdown.expanded = false
    end
    collapseOutside(x, y)

    -- activate text boxes
    titleBox.active = contains(titleBox, x, y)
    noteBox.active = contains(noteBox, x, y)
    if noteBox.active then
        setCaretFromClick(x, y)
    end

    if contains(saveBtn, x, y) then
        saveNote()
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

local function drawDropdown()
    ------------------------------------------------------------------
    -- Base field ----------------------------------------------------
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
    love.graphics.setColor(BORDER_COLOR)
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

    ------------------------------------------------------------------
    -- Text label (“art”, “hacking”…)
    love.graphics.setColor(0, 0, 0)
    love.graphics.printf(
        dropdown.selected,
        dropdown.x + 12,
        dropdown.y + 10,
        dropdown.w - ARROW_W - 12, -- give arrow area its space
        "left"
    )

    ------------------------------------------------------------------
    -- Arrow button area --------------------------------------------
    local arrowX = dropdown.x + dropdown.w - ARROW_W
    local hover = contains(
        { x = arrowX, y = dropdown.y, w = ARROW_W, h = dropdown.h },
        love.mouse.getPosition()
    )

    -- Subtle grey background that brightens on hover
    if hover then
        love.graphics.setColor(0.90, 0.90, 0.90)
    else
        love.graphics.setColor(0.95, 0.95, 0.95)
    end
    love.graphics.rectangle(
        "fill",
        arrowX,
        dropdown.y,
        ARROW_W,
        dropdown.h,
        8,
        8
    )

    -- Vertical separator line
    love.graphics.setColor(BORDER_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.line(
        arrowX,
        dropdown.y + 4,
        arrowX,
        dropdown.y + dropdown.h - 4
    )

    -- Arrow icon (triangle) – rotates when expanded
    local midX = arrowX + ARROW_W / 2
    local midY = dropdown.y + dropdown.h / 2
    love.graphics.setColor(0.2, 0.2, 0.2)

    if dropdown.expanded then
        -- UP-pointing triangle
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
        -- DOWN-pointing triangle
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

    ------------------------------------------------------------------
    -- Expanded option list (unchanged) ------------------------------
    if dropdown.expanded then
        love.graphics.setColor(DROPDOWN_BG)
        love.graphics.rectangle(
            "fill",
            dropdown.x,
            dropdown.y + dropdown.h,
            dropdown.w,
            #CATEGORY_OPTIONS * OPTION_H,
            8,
            8
        )
        love.graphics.setColor(BORDER_COLOR)
        love.graphics.rectangle(
            "line",
            dropdown.x,
            dropdown.y + dropdown.h,
            dropdown.w,
            #CATEGORY_OPTIONS * OPTION_H,
            8,
            8
        )

        for i, opt in ipairs(CATEGORY_OPTIONS) do
            local oy = dropdown.y + dropdown.h + (i - 1) * OPTION_H
            love.graphics.setColor(0, 0, 0)
            love.graphics.printf(
                opt,
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
    love.graphics.printf(
        noteText,
        noteBox.x + 12,
        noteBox.y + 12,
        noteBox.w - 24,
        "left"
    )

    -- caret  (drawn in the translated space → no extra scroll math)
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

    drawInput(titleBox)
    love.graphics.setColor(0, 0, 0)
    love.graphics.printf(
        titleText,
        titleBox.x + 12,
        titleBox.y + 12,
        titleBox.w - 24,
        "left"
    )

    drawNoteBox()
    drawDropdown()

    love.graphics.setColor(hoverBtn and BTN_COL_HOVER or BTN_COLOR)
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
end

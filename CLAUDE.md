# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Zet is a zettelkasten note-taking desktop application built with Lua and LÖVE 2D (Love2D) framework. It provides a GUI for creating and managing structured notes with title, category, description, tags, and content fields.

## Build and Development Commands

```bash
make install     # Install dependencies from rockspec with luarocks
make run         # Run the application (sources project.env, launches with 'love .')
make release     # Build zet.love bundle and install system-wide to ~/.local/
make lint        # Run luacheck on src/
make format      # Run stylua formatting on src/
make docs        # Generate documentation with ldoc
```

## Architecture

### Application Structure

- **main.lua** - Monolithic main file containing all UI logic, state management, and Love2D lifecycle hooks
- **src/file-utils.lua** - File I/O utilities (read_file, write_file)
- **src/templates/engine.lua** - Template compilation engine supporting `{{ expr }}` and `{% code %}` syntax
- **src/setup.lua** - Lua module path configuration for packed/unpacked environments

### Love2D Lifecycle

The app implements standard Love2D callbacks:
- `love.load()` - Initialize UI components, fonts, window
- `love.update(dt)` - Update hover states
- `love.draw()` - Render UI elements
- `love.keypressed(key)` - Keyboard shortcuts and navigation
- `love.textinput(t)` - Character input handling
- `love.mousepressed/mousemoved/wheelmoved` - Mouse interaction

### UI State Model

All UI elements (titleBox, dropdown, descBox, tagsBox, noteBox) are rectangle-based with x, y, w, h coordinates. Focus cycles through FIELDS array via TAB. Text editing uses UTF-8 with caret position tracking (caretPos) and selection range (selStart, selEnd).

## Dependencies (via Luarocks)

- lua ~> 5.1
- lua-yaml 1.2-2
- ldoc 1.5.0-1
- inspect >= 3.1
- debugger scm-1

## Commit Convention

Uses devmoji for emoji-based commits (configured in .pre-commit-config.yaml).

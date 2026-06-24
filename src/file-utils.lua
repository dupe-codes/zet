local M = {}

function M.read_file(path)
    local file = io.open(path, "r")
    if not file then
        error("Could not open file: " .. path)
    end
    local content = file:read "*a"
    file:close()
    return content
end

--- Create `dir_path` and any missing parents (the `mkdir -p` contract).
-- The bins resolver hands back vault-relative subtrees (e.g.
-- `chassis/knowledge/inbox`) that need not already exist in the chosen vault,
-- so a write into one would otherwise fail until the user hand-created the
-- tree. Idempotent: an already-present directory is a success.
-- @return true                 on success (including dir already present)
-- @return nil, errmsg          if the directory could not be created
function M.make_dir(dir_path)
    assert(
        type(dir_path) == "string" and dir_path ~= "",
        "make_dir requires a directory path"
    )
    -- Single-quote the path so spaces and shell metacharacters in vault paths
    -- are passed literally; an embedded single quote is escaped by closing the
    -- quote, inserting a backslash-escaped quote, and reopening: '\''.
    local quoted = "'" .. dir_path:gsub("'", "'\\''") .. "'"
    local result = os.execute("mkdir -p -- " .. quoted)
    -- os.execute returns the raw exit code under Lua 5.1 / LuaJIT (the LÖVE
    -- runtime) and a boolean under 5.2+. Accept either success signal.
    if result == true or result == 0 then
        return true
    end
    return nil, "could not create directory: " .. dir_path
end

--- Write `output` to `output_file_path` **only if the file does not exist**.
-- The parent directory tree is created on demand first, so callers may target
-- a vault bin that has not been materialised yet.
-- @return true                 on success
-- @return nil, "exists"        if the file already exists
-- @return nil, errmsg          for any other I/O error
function M.write_file(output_file_path, output)
    assert(
        type(output_file_path) == "string" and output_file_path ~= "",
        "write_file requires a destination path"
    )

    local test = io.open(output_file_path, "r")
    if test then
        test:close()
        return nil, "exists"
    end

    -- Materialise the destination directory before opening for write. The
    -- parent is everything up to the final `/`; a bare filename has no parent
    -- and writes into the current directory unchanged.
    local parent_dir = output_file_path:match "^(.*)/[^/]+$"
    if parent_dir and parent_dir ~= "" then
        local made, mkdir_err = M.make_dir(parent_dir)
        if not made then
            return nil, mkdir_err
        end
    end

    local file, err = io.open(output_file_path, "w")
    if not file then
        return nil, err -- e.g. permission denied
    end

    local ok, writeErr = file:write(output)
    file:close()

    if not ok then
        return nil, writeErr
    end
    return true
end

return M

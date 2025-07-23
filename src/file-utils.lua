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

--- Write `output` to `output_file_path` **only if the file does not exist**.
-- @return true                 on success
-- @return nil, "exists"        if the file already exists
-- @return nil, errmsg          for any other I/O error
function M.write_file(output_file_path, output)
    local test = io.open(output_file_path, "r")
    if test then
        test:close()
        return nil, "exists"
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

-- copied and adapted from https://nachtimwald.com/2014/08/06/using-lua-as-a-templating-engine/
-- TODO: replace with a scanner => parser => interpreter approach

local M = {}

local function append(builder, text, code)
    if code then
        builder[#builder + 1] = code
    else
        builder[#builder + 1] = "_ret[#_ret+1] = [[\n" .. text .. "]]"
    end
end

local function run_block(builder, text)
    local fn = nil

    local tag = text:sub(1, 2)
    if tag == "{{" then
        fn = function(code)
            return ("_ret[#_ret+1] = %s"):format(code)
        end
    elseif tag == "{%" then
        fn = function(code)
            return code
        end
    end

    if fn then
        append(builder, nil, fn(text:sub(3, #text - 3)))
    else
        append(builder, text)
    end
end

--[[
--  Example template:
--
--    <p>{{ name }}</p>
--    <ul>
--    {{% for _, t in ipairs(items) do }}
--        <li> {{ t }} </li>
--    {{ end }}
--    </ul>
--
--]]
function M.compile_template(template_str, env)
    if env then
        -- ensure table is present in env, since we always refer to it
        -- TODO: add validation that "table" is not used as identifier
        --       in the user template
        env["table"] = table
    end

    local builder = { "_ret = {}\n" }

    if #template_str == 0 then
        return ""
    end

    local position = 1
    while position < #template_str do
        local block_start = template_str:find("{", position)
        if not block_start then
            break
        end

        -- check if escaped block
        if template_str:sub(block_start - 1, block_start - 1) == "\\" then
            -- TODO: what if escaped block is right at beginning?
            append(builder, template_str:sub(position, block_start - 2))
            append(builder, "{")
            position = block_start + 1
        else
            append(builder, template_str:sub(position, block_start - 1))

            position = template_str:find("}}", block_start)

            if not position then
                append(builder, "Missing end tag ('}}')")
                break
            end

            run_block(builder, template_str:sub(block_start, position + 2))
            position = position + 2
        end
    end

    if position then
        append(builder, template_str:sub(position, #template_str))
    end

    builder[#builder + 1] = "return table.concat(_ret)"

    local func, err = load(table.concat(builder, "\n"), "template", "t", env)
    if not func then
        return err
    end

    return func()
end

function M.compile_template_file(template_file, env)
    local file = io.open(template_file, "rb")
    if not file then
        error("Could not open template file: " .. template_file)
    end
    local template = file:read "*all"
    file:close()
    return M.compile_template(template, env)
end

return M

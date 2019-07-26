
--!A cross-platform build utility based on Lua
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
-- Copyright (C) 2015 - 2019, TBOOX Open Source Group.
--
-- @author      OpportunityLiu
-- @file        serialize.lua
--

-- define module: serialize
local serialize = serialize or {}
local _ENV      = serialize._ENV or {}

-- load modules
local math      = require("base/math")
local table     = require("base/table")

-- save original interfaces
serialize._dump = serialize._dump or string._dump or string.dump

-- init env
_ENV.nan = math.nan
_ENV.inf = math.huge

function serialize._createstub(resolver, ...)
    _ENV.has_stub = true
    local params = table.pack(...)
    return function(root, env)
        return resolver(root, env, table.unpack(params, 1, params.n))
    end
end

function serialize._resolvestub(object, root, env)
    if type(object) == "function" then
        local ok, result, errors = pcall(object, root, env)
        if ok and errors == nil then
            return result
        end
        return nil, errors or result or "unspecified error"
    end
    if type(object) ~= "table" then
        return object
    end

    for k, v in pairs(object) do
        local result, errors = serialize._resolvestub(v, root, env)
        if errors ~= nil then
            return nil, errors
        end
        object[k] = result
    end
    return object
end

function serialize._makestring(str, opt)
    return string.format("%q", str)
end

function serialize._makedefault(val, opt)
    return tostring(val)
end

function serialize._maketable(object, opt, level, path, reftab)

    level = level or 0
    reftab = reftab or {}
    path = path or {}
    reftab[object] = table.copy(path)

    -- serialize child items
    local childlevel = level + 1
    local serialized = {}
    local numidxcount = 0
    local isarr = true
    local maxn = 0
    for k, v in pairs(object) do
        -- check key
        if type(k) == "number" then
            -- only checks when it may be an array
            if isarr then
                numidxcount = numidxcount + 1
                if k < 1 or not math.isint(k) then
                    isarr = false
                elseif k > maxn then
                    maxn = k
                end
            end
        elseif type(k) == "string" then
            isarr = false
        else
            return nil, string.format("cannot serialize table with key of %s: <%s>", type(k), k)
        end

        -- serialize value
        local sval, err
        if type(v) == "table" then
            if reftab[v] then
                sval, err = serialize._makeref(reftab[v], opt)
            else
                table.insert(path, k)
                sval, err = serialize._maketable(v, opt, childlevel, path, reftab)
                table.remove(path)
            end
        else
            sval, err = serialize._make(v, opt)
        end
        if err ~= nil then
            return nil, err
        end
        serialized[k] = sval
    end

    -- too sparse
    if numidxcount * 2 < maxn then
        isarr = false
    end

    -- make indent
    local indent = ""
    if opt.indent then
        indent = string.rep(opt.indent, level)
    end

    -- make head
    local headstr = opt.indent and ("{\n" .. indent .. opt.indent)  or "{"

    -- make tail
    local tailstr
    if opt.indent then
        tailstr = "\n" .. indent .. "}"
    else
        tailstr = "}"
    end

    -- make body
    local bodystrs = {}
    if isarr then
        for i = 1, maxn do
            bodystrs[i] = serialized[i] or "nil"
        end
    else
        local con = opt.indent and " = " or "="
        for k, v in pairs(serialized) do
            -- serialize key
            if type(k) == "string" then
                if not k:match("^[%a_][%w_]*$") then
                    k = string.format("[%q]", k)
                end
            else -- type(k) == "number"
                local nval, err = serialize._makedefault(k, opt, childlevel)
                if err ~= nil then
                    return nil, err
                end
                k = string.format("[%s]", nval)
            end
            -- concat k = v
            table.insert(bodystrs, k .. con .. v)
        end
    end

    if #bodystrs == 0 then
        return opt.indent and "{ }" or "{}"
    end
    return headstr .. table.concat(bodystrs, opt.indent and (",\n" .. indent .. opt.indent) or ",") .. tailstr
end

function serialize._makefunction(func, opt)

    local ok, funccode = pcall(serialize._dump, func, opt.strip)
    if not ok then
        return nil, string.format("%s: <%s>", funccode, func)
    end
    return string.format("func%q", funccode)
end

function serialize._resolvefunction(root, env, funccode)
    return load(funccode, "=(deserialized code)", "b", env)
end

-- load function
function _ENV.func(funccode)
    -- type guard
    assert(type(funccode) == "string", "func should called with a string")
    -- load func
    return serialize._createstub(serialize._resolvefunction, funccode)
end

function serialize._makeref(path, opt)

    -- root reference
    if path[1] == nil then
        return "ref()"
    end

    local ppath = {}
    for i, v in ipairs(path) do
        ppath[i] = serialize._make(v, opt)
    end

    return "ref(" .. table.concat(ppath, opt.indent and ", " or ",") .. ")"
end

function serialize._resolveref(root, env, ...)
    local pos = root
    for i, v in ipairs({...}) do
        if type(pos) ~= "table" then
            return nil, "unable to resolve path: <root>." .. table.concat(path, ".", 1, i - 1) .. " is " .. tostring(pos)
        end
        pos = pos[v]
    end
    return pos
end

-- reference
function _ENV.ref(...)
    -- load func
    return serialize._createstub(serialize._resolveref, ...)
end


-- make string with the level
function serialize._make(object, opt)

    -- call make* by type
    if type(object) == "string" then
        return serialize._makestring(object, opt)
    elseif type(object) == "boolean" or type(object) == "nil" or type(object) == "number" then
        return serialize._makedefault(object, opt)
    elseif type(object) == "table" then
        return serialize._maketable(object, opt)
    elseif type(object) == "function" then
        return serialize._makefunction(object, opt)
    else
        return nil, string.format("cannot serialize %s: <%s>", type(object), object)
    end
end

-- serialize to string from the given object
--
-- @param opt           serialize options
--
-- @return              string, errors
--
function serialize.save(object, opt)

    -- init options
    if opt == true then
        opt = { strip = true, binary = false, indent = false }
    elseif not opt then
        opt = {}
    end

    if opt.strip == nil then opt.strip = false end
    if opt.binary == nil then opt.binary = false end
    if opt.indent == nil then opt.indent = true end

    -- init indent, from nil, boolean, number or string to false or string
    if not opt.indent then
        -- no indent
        opt.indent = false
    elseif type(opt.indent) == "boolean" then -- true
        -- 4 spaces
        opt.indent = "    "
    elseif type(opt.indent) == "number" then
        if opt.indent < 0 then
            opt.indent = false
        elseif opt.indent > 20 then
            return nil, "invalid opt.indent, too large"
        else
            -- opt.indent spaces
            opt.indent = string.rep(" ", opt.indent)
        end
    elseif type(opt.indent) == "string" then
        -- only whitespaces allowed
        if not opt.indent:match("^%s+$") then
            return nil, "invalid opt.indent, only whitespaces are accepted"
        end
    else
        return nil, "invalid opt.indent, should be boolean, number or string"
    end

    -- make string
    local ok, result, errors = pcall(serialize._make, object, opt)
    if not ok then
        errors = "cannot serialize: " .. result
    end

    -- ok?
    if errors ~= nil then
        return nil, errors
    end

    if not opt.binary then
        return result
    end

    -- binary mode
    local func, lerr = loadstring("return " .. result)
    if lerr ~= nil then
        return nil, lerr
    end

    local dump, derr = serialize._dump(func, true)
    if derr ~= nil then
        return nil, derr
    end

    -- return shorter representation
    return (#dump < #result) and dump or result
end

-- load table from string in table
function serialize._load(str)

    -- load table as script
    local result = nil
    local binary = str:startswith("\27LJ")
    if not binary then
        str = "return " .. str
    end

    -- load string
    local script, errors = load(str, "=(deserializing data)", binary and "b" or "t", _ENV)
    if script then
        -- load object
        local ok, object = pcall(script)
        if ok then
            result = object
            if _ENV.has_stub then
                _ENV.has_stub = false
                local env = debug.getfenv(debug.getinfo(3, "f").func)
                result, errors = serialize._resolvestub(result, result, env)
            end
        else
            -- error
            errors = tostring(object)
        end
    end

    if errors then
        local data
        if binary then
            data = "<binary data>"
        elseif #str > 30 then
            data = string.format("%q... ", str:sub(8, 27))
        else
            data = string.format("%q", str:sub(8))
        end
        -- error
        return nil, string.format("cannot deserialize %s: %s", data, errors)
    end

    return result
end

-- deserialize string to object
--
-- @param str           the serialized string
--
-- @return              object, errors
--
function serialize.load(str)

    -- check
    assert(str)

    -- load string
    local result, errors = serialize._load(str)
    if errors ~= nil then
        return nil, errors
    end
    return result
end

-- return module: serialize
serialize._ENV = _ENV
return serialize

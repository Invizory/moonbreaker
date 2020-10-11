-- Workaround for Lua 5.1, which lacks xpcall with arguments.
local function xpcall1(f, msgh, ...)
    local args = {...}
    return xpcall(function()
        return f(unpack(args))
    end, msgh)
end

xpcall(function(ok)
    if ok then
        xpcall1 = xpcall
    end
end, function() end, true)

return xpcall1

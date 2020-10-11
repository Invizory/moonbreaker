local oop = require "moonbreaker.oop"


local Clock = oop.class()

function Clock:__new(time)
    return {
        _time = time or 1,
    }
end

function Clock:__call()
    return self._time
end

function Clock:advance(delta)
    self._time = self._time + delta
end


local Service = oop.class()

function Service:__new(params)
    params = params or {}
    return {
        _ok = params.ok == nil or params.ok,
    }
end

function Service:repair()
    self._ok = true
end

function Service:crush()
    self._ok = false
end

function Service:__call()
    if self._ok then
        return true
    else
        return false, "error"
    end
end


return {
    Clock = Clock,
    Service = Service,
}

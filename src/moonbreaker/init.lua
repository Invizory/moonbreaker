local oop = require "moonbreaker.oop"
local xpcall = require "moonbreaker.xpcall"
local table = require "std.table"


local Counters = oop.class()

function Counters:__new()
    return {
        requests = 0,
        total_successes = 0,
        total_failures = 0,
        consecutive_successes = 0,
        consecutive_failures = 0,
    }
end

function Counters:total_samples()
    return self.total_successes + self.total_failures
end

function Counters:_on_request()
    self.requests = self.requests + 1
end

function Counters:_on_success()
    self.total_successes = self.total_successes + 1
    self.consecutive_successes = self.consecutive_successes + 1
    self.consecutive_failures = 0
end

function Counters:_on_failure()
    self.total_failures = self.total_failures + 1
    self.consecutive_failures = self.consecutive_failures + 1
    self.consecutive_successes = 0
end


local states = {
    closed = "closed",
    open = "open",
    half_open = "half_open",
}
local errors = {
    open = "Circuit Breaker is open",
    too_many_requests = "Circuit Breaker reports too many requests",
}


local on = {}

function on.consecutive_failures(limit)
    return function(counters)
        return counters.consecutive_failures >= limit
    end
end

function on.total_failures(limit)
    return function(counters)
        return counters.total_failures >= limit
    end
end

function on.total_failures_rate(params)
    return function(counters)
        local samples = counters:total_samples()
        return samples >= params.min_samples and
               counters.total_failures / samples >= params.rate
    end
end

function on.consecutive_successes(limit)
    return function(counters)
        return counters.consecutive_successes >= limit
    end
end


local success = {}

function success.truthy(value)
    return value
end

function success.falsy_err(_, err)
    return not err
end

function success.always()
    return true
end


local error_reporting = {}

function error_reporting.nil_err(err)
    return nil, err
end

function error_reporting.false_err(err)
    return false, err
end

function error_reporting.error(err)
    error(err, 2)
end


local CircuitBreaker = oop.class()

function CircuitBreaker:__new(settings) -- luacheck: ignore 561
    settings = settings or {}
    local limit = settings.limit or 10
    return {
        _limit = limit,
        _timeout = settings.timeout or 60,
        _interval = settings.interval or 0,
        _should_open = settings.should_open or
                       on.consecutive_failures(limit),
        _should_close = settings.should_close or
                        on.consecutive_successes(limit),
        _success = settings.success or success.truthy,
        _error = settings.error or error_reporting.nil_err,
        _error_handler = settings.error_handler or debug.traceback,
        _rethrow = settings.rethrow or error,
        _now = settings.now or os.time,
        _notify = settings.notify or function() end,
        _state = states.closed,
        _counters = Counters(),
        _generation = 0,
        _expiry = 0,
    }
end

function CircuitBreaker:__call(...)
    return self:wrap(...)
end

function CircuitBreaker:wrap(target)
    return setmetatable({}, {
        __index = self,
        __call = function(_, ...)
            return self:execute(target, ...)
        end
    })
end

function CircuitBreaker:execute(target, ...)
    local err = self:_before()
    if err then
        return self._error(err)
    end
    local previous_generation = self._generation
    local values = {xpcall(target, self._error_handler, ...)}
    local ok = values[1]
    if not ok then
        err = values[2]
        self:_after(previous_generation, false)
        return self._rethrow(err)
    end
    ok = self._success(table.unpack(values, 2))
    self:_after(previous_generation, ok)
    return table.unpack(values, 2)
end

function CircuitBreaker:state()
    self:_update_state()
    return self._state
end

function CircuitBreaker:_before()
    self:_update_state()
    if self._state == states.open then
        return errors.open
    elseif self._state == states.half_open and
           self._counters.requests >= self._limit then
        return errors.too_many_requests
    end
    self._counters:_on_request()
    return nil
end

function CircuitBreaker:_after(previous_generation, is_success)
    self:_update_state()
    if self._generation ~= previous_generation then
        return
    end
    if is_success then
        self:_on_success()
    else
        self:_on_failure()
    end
end

function CircuitBreaker:_update_state()
    if not (self._expiry <= self._now()) then
        return
    end
    if self._state == states.closed and self._expiry > 0 then
        self:_next_generation()
    elseif self._state == states.open then
        self:_set_state(states.half_open)
    end
end

function CircuitBreaker:_on_success()
    self._counters:_on_success()
    if self._state == states.half_open and
       self._should_close(self._counters) then
        self:_set_state(states.closed)
    end
end

function CircuitBreaker:_on_failure()
    self._counters:_on_failure()
    if self._state == states.closed and self._should_open(self._counters) or
       self._state == states.half_open then
        self:_set_state(states.open)
    end
end

function CircuitBreaker:_set_state(new_state)
    self._state = new_state
    self:_next_generation()
    self:_notify(new_state)
end

function CircuitBreaker:_next_generation()
    self._generation = self._generation + 1
    self._counters = Counters()
    self._expiry = 0
    if self._state == states.closed and self._interval > 0 then
        self._expiry = self._now() + self._interval
    elseif self._state == states.open then
        self._expiry = self._now() + self._timeout
    end
end


return setmetatable({
    new = CircuitBreaker,
    on = on,
    success = success,
    error_reporting = error_reporting,
    states = states,
    errors = errors,
}, {
    __call = function(self, ...)
        return self.new(...)
    end
})

local moonbreaker = require "moonbreaker"
local mocks = require "spec.mocks"

describe("moonbreaker", function()
    local limit, timeout = 5, 30

    local clock, breaker
    before_each(function()
        clock = mocks.Clock()
        breaker = moonbreaker {
            limit = limit,
            timeout = timeout,
            now = clock,
        }
    end)

    local function failure()
        return nil, "error"
    end

    local function exceptional()
        error("omg")
    end

    describe("state()", function()
        it("should be closed initially", function()
            assert.are.same(moonbreaker.states.closed, breaker:state())
        end)

        it("should remain closed after just a couple of failures", function()
            local fun = breaker(failure)
            for _ = 1, limit - 1 do fun() end
            assert.are.same(moonbreaker.states.closed, breaker:state())
        end)

        it("should open after too many failures", function()
            local fun = breaker(failure)
            for _ = 1, limit do fun() end
            assert.are.same(moonbreaker.states.open, breaker:state())
        end)

        it("should be open before timeout", function()
            local fun = breaker(failure)
            for _ = 1, limit do fun() end
            clock:advance(timeout - 1)
            assert.are.same(moonbreaker.states.open, breaker:state())
        end)

        it("should be half-open after timeout", function()
            local fun = breaker(failure)
            for _ = 1, limit do fun() end
            clock:advance(timeout)
            assert.are.same(moonbreaker.states.half_open, breaker:state())
        end)

        it("should be open after failed test", function()
            local fun = breaker(failure)
            for _ = 1, limit do fun() end
            clock:advance(timeout)
            fun()
            assert.are.same(moonbreaker.states.open, breaker:state())
        end)

        it("should close after recovery", function()
            local service = mocks.Service()
            local fun = breaker(service)
            service:crush()
            for _ = 1, limit do fun() end
            clock:advance(timeout)
            service:repair()
            for _ = 1, limit do fun() end
            assert.are.same(moonbreaker.states.closed, breaker:state())
        end)
    end)

    context("proxying", function()
        it("should call target function with the same arguments", function()
            local target = spy.new()
            local fun = breaker(target)
            fun(1, nil, 3)
            assert.spy(target).was.called_with(1, nil, 3)
        end)

        it("should call target function and return the same values", function()
            local fun = breaker(function() return 1, nil, 3 end)
            assert.are.same({1, nil, 3}, {fun()})
        end)

        it("should return original error after just a couple of failures",
           function()
            local fun = breaker(failure)
            for _ = 1, limit - 1 do
                assert.are.same({nil, "error"}, {fun()})
            end
        end)

        it("should call function to try to recover after timeout", function()
            local target = spy.new(failure)
            local fun = breaker(target)
            for _ = 1, limit do fun() end
            clock:advance(timeout)
            fun("secret")
            assert.spy(target).was.called_with("secret")
        end)

        it("should rethrow exception", function()
            local fun = breaker(exceptional)
            assert.has_error(fun)
        end)
    end)

    context("errors", function()
        it("should open after too many failures", function()
            local fun = breaker(failure)
            for _ = 1, limit do fun() end
            assert.are.same({nil, moonbreaker.errors.open}, {fun()})
        end)

        it("should open after too many exceptions", function()
            local fun = breaker(exceptional)
            for _ = 1, limit do pcall(fun) end
            assert.are.same({nil, moonbreaker.errors.open}, {fun()})
        end)
    end)
end)

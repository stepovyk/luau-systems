--!strict
-- Lightweight signal. Handlers run in their own thread, so a yielding or erroring
-- handler never blocks the code that fired the signal.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _handlers = {} :: { any } }, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal:Connect(handler)
	local connection
	connection = {
		Connected = true,
		_handler = handler,
		Disconnect = function(conn)
			if not conn.Connected then
				return
			end
			conn.Connected = false
			local index = table.find(self._handlers, conn)
			if index then
				table.remove(self._handlers, index)
			end
		end,
	}
	table.insert(self._handlers, connection)
	return connection
end

function Signal:Once(handler)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Fire(...)
	-- Snapshot so handlers may disconnect themselves while we iterate.
	for _, connection: any in table.clone(self._handlers) do
		if connection.Connected then
			task.spawn(connection._handler, ...)
		end
	end
end

function Signal:DisconnectAll()
	for _, connection in self._handlers do
		connection.Connected = false
	end
	table.clear(self._handlers)
end

return Signal

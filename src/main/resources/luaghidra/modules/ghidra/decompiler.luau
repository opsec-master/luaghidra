-- Decompilation.
--
--     local result = ghidra.decompile(func)
--     if result.ok then
--         print(result.c)
--     else
--         ghidra.warn(result.error)
--     end
--
-- The decompiler process is created on first use and reused for the rest of the
-- session, so decompiling many functions does not pay the startup cost each time.

local internal = require("@ghidra/internal/host")

local decompiler = {}

export type DecompileResult = {
	ok: boolean,
	c: string?,
	signature: string?,
	error: string?,
	results: any?,
	highFunction: any?,
}

--- Decompiles a function.
---
--- Options: `timeout` in seconds (default 30).
--- Returns `{ ok = true, c, signature, results, highFunction }` on success and
--- `{ ok = false, error }` on failure, so callers never need pcall for the
--- ordinary "this function would not decompile" case.
function decompiler.decompile(func, options: { timeout: number? }?): DecompileResult
	if func == nil then
		error("decompile expects a function", 2)
	end
	local context = internal.context()
	local timeout = (options and options.timeout) or 30

	local ok, results = pcall(function()
		return context:getDecompiler():decompileFunction(func, timeout, context:getMonitor())
	end)
	if not ok then
		return { ok = false, error = tostring(results) }
	end
	if results == nil then
		return { ok = false, error = "the decompiler returned no result" }
	end
	if not results:decompileCompleted() then
		local message = results:getErrorMessage()
		return { ok = false, error = if message ~= nil and message ~= "" then message else "decompilation did not complete" }
	end

	local decompiled = results:getDecompiledFunction()
	return {
		ok = true,
		c = if decompiled ~= nil then decompiled:getC() else "",
		signature = if decompiled ~= nil then decompiled:getSignature() else nil,
		results = results,
		highFunction = results:getHighFunction(),
	}
end

--- The shared DecompInterface, for options and APIs this module does not wrap.
function decompiler.interface()
	return internal.context():getDecompiler()
end

--- Releases the decompiler process. It is recreated on the next decompile.
function decompiler.dispose()
	internal.context():disposeDecompiler()
end

return decompiler

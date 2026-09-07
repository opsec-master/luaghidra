-- Running other programs.
--
--     local process = require("@ghidra/process")
--
--     for line in process.lines({ "yara", rules, path }) do
--         print(line)
--     end
--
-- Reverse engineering scripts lean on the tools already installed next to
-- Ghidra -- yara, binwalk, a demangler, a disassembler -- and Luau has no
-- os.execute or io.popen, so this fills that gap using the JVM's process API.
--
-- A command is an array: the program first, then one argument per element. It is
-- never handed to a shell, so arguments with spaces, quotes, or globs in them
-- reach the program exactly as written.

local internal = require("@ghidra/internal/host")

local process = {}

export type Options = {
	input: string?,
	cwd: any?,
	env: { [string]: string }?,
	timeout: number?,
	stderr: boolean?,
}

export type Result = {
	ok: boolean,
	code: number,
	stdout: string,
	stderr: string,
}

local function classes()
	return internal.classes
end

local function textOf(bytes): string
	return tostring(java.new(java.import("java.lang.String"), bytes))
end

local function builderFor(command: { string }, options: Options)
	if typeof(command) ~= "table" or #command == 0 then
		error("a command is an array: the program, then its arguments", 3)
	end
	local list = java.new(java.import("java.util.ArrayList"))
	for _, part in command do
		list:add(tostring(part))
	end

	local builder = classes()["java.lang.ProcessBuilder"](list)
	if options.stderr == false then
		builder:redirectErrorStream(false)
	end
	if options.cwd ~= nil then
		builder:directory(classes()["java.io.File"](tostring(options.cwd)))
	end
	if options.env ~= nil then
		local environment = builder:environment()
		for key, value in options.env do
			environment:put(key, tostring(value))
		end
	end
	return builder
end

--- Runs a command and waits for it to finish.
---
--- Options: `input` to write to its standard input, `cwd` to run it somewhere,
--- `env` to add environment variables, `timeout` in seconds (the process is
--- destroyed if it overruns), and `stderr = false` to keep the error stream out
--- of `stdout` and collect it separately.
---
--- Returns `{ ok, code, stdout, stderr }` rather than raising, so a command that
--- exits non-zero -- which many tools do to report "nothing found" -- needs no
--- pcall.
function process.run(command: { string }, options: Options?): Result
	local settings = options or {}
	local separate = settings.stderr == false
	local builder = builderFor(command, settings)
	if not separate then
		builder:redirectErrorStream(true)
	end

	local ok, running = pcall(function()
		return builder:start()
	end)
	if not ok then
		return { ok = false, code = -1, stdout = "", stderr = tostring(running) }
	end

	if settings.input ~= nil then
		local stream = running:getOutputStream()
		-- A Luau string arrives in Java as a String, so the bytes are built here.
		local text = settings.input
		local payload = java.array(java.import("byte"), #text)
		for index = 1, #text do
			payload[index] = string.byte(text, index) % 256
		end
		stream:write(payload)
		stream:close()
	else
		running:getOutputStream():close()
	end

	local out = textOf(running:getInputStream():readAllBytes())
	local err = if separate then textOf(running:getErrorStream():readAllBytes()) else ""

	if settings.timeout ~= nil then
		local TimeUnit = classes()["java.util.concurrent.TimeUnit"]
		if not running:waitFor(settings.timeout, TimeUnit.SECONDS) then
			running:destroyForcibly()
			return {
				ok = false,
				code = -1,
				stdout = out,
				stderr = `timed out after {settings.timeout}s`,
			}
		end
	else
		running:waitFor()
	end

	local code = running:exitValue()
	return { ok = code == 0, code = code, stdout = out, stderr = err }
end

--- Runs a command and returns what it printed, raising when it fails. This is
--- the shape most scripts want: the tool either answers or the script stops.
function process.output(command: { string }, options: Options?): string
	local result = process.run(command, options)
	if not result.ok then
		local detail = if result.stderr ~= "" then result.stderr else result.stdout
		error(`{command[1]} failed ({result.code}): {detail}`, 2)
	end
	return result.stdout
end

--- Iterates the lines a command prints, raising when it fails.
function process.lines(command: { string }, options: Options?)
	local text = process.output(command, options)
	local index = 0
	local lines = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(lines, line)
	end
	if #lines > 0 and lines[#lines] == "" then
		lines[#lines] = nil
	end
	return function(): string?
		index += 1
		return lines[index]
	end
end

--- The full path of a program on PATH, or nil when it is not installed. Worth
--- checking before a script tells the user to install something.
function process.which(program: string): string?
	local separator = classes()["java.io.File"].pathSeparator
	local path = classes()["java.lang.System"]:getenv("PATH")
	if path == nil then
		return nil
	end
	for directory in string.gmatch(path, `([^{separator}]+)`) do
		local candidate = classes()["java.io.File"](directory, program)
		if candidate:canExecute() then
			return tostring(candidate)
		end
	end
	return nil
end

return process

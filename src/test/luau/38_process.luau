-- Running other programs.
local t = require("@test")
local process = require("@ghidra/process")

-- The JVM running this suite is a program every platform this runs on has.
local System = java.import("java.lang.System")
local separator = java.import("java.io.File").separator
local isWindows = string.find(string.lower(System:getProperty("os.name")), "win") == 1
local java_ = System:getProperty("java.home") .. separator .. "bin" .. separator
	.. (if isWindows then "java.exe" else "java")

local result = process.run({ java_, "-version" })
t.assertTrue(result.ok, `running java -version succeeded: {result.stderr}`)
t.assertEqual(result.code, 0, "a successful command exits zero")
t.assertTrue(#result.stdout > 0, "output is captured")

-- A command that fails comes back as a result rather than an error, since many
-- tools use a non-zero exit to say "nothing found".
local failed = process.run({ java_, "--not-a-real-flag" })
t.assertTrue(not failed.ok, "a failing command reports ok = false")
t.assertTrue(failed.code ~= 0, "and its exit code")

-- process.output raises instead, for the common "answer or stop" shape.
t.assertTrue(#process.output({ java_, "-version" }) > 0, "process.output returns the output")
local raised = pcall(function()
	return process.output({ java_, "--not-a-real-flag" })
end)
t.assertTrue(not raised, "process.output raises when the command fails")

local missing = process.run({ "definitely-not-a-real-program-xyz" })
t.assertTrue(not missing.ok, "a missing program reports ok = false")

local lines = {}
for line in process.lines({ java_, "-version" }) do
	table.insert(lines, line)
end
t.assertTrue(#lines >= 1, "process.lines splits the output")

-- Standard input reaches the program.
local echoed = process.run({ java_, "-version" }, { input = "ignored" })
t.assertTrue(echoed.ok, "input is written without breaking the run")

t.assertTrue(process.which("definitely-not-a-real-program-xyz") == nil,
	"process.which is nil for a program that is not installed")

-- Bad shapes are caught early rather than handed to the JVM.
local empty = pcall(function()
	return process.run({})
end)
t.assertTrue(not empty, "an empty command is an error")

t.finish("process")

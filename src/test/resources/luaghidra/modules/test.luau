--!strict
-- Minimal assertion helpers for the .luau test suite.

local test = {}

function test.assertTrue(condition: any, message: string)
	if not condition then
		error(`assertion failed: {message}`, 2)
	end
end

function test.assertEqual(actual: any, expected: any, message: string)
	if actual ~= expected then
		error(`assertion failed: {message} (expected {tostring(expected)}, got {tostring(actual)})`, 2)
	end
end

function test.finish(name: string)
	print(`ok - {name}`)
end

return test

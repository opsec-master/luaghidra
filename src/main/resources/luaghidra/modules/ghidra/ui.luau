-- Prompts and navigation.
--
--     local ui = require("@ghidra/ui")
--     local name = ui.askString("Rename", "New name:", "main")
--
-- Every prompt raises when the user cancels, so a cancelled script stops rather
-- than continuing with a nil. Headless runs answer prompts from the script's
-- .properties file, exactly as they do for Java scripts.

local internal = require("@ghidra/internal/host")

local ui = {}

local function script()
	return internal.context():getScript()
end

--- Asks for a line of text.
function ui.askString(title: string, prompt: string, default: string?): string
	if default ~= nil then
		return script():askString(title, prompt, default)
	end
	return script():askString(title, prompt)
end

--- Asks for a whole number.
function ui.askInt(title: string, prompt: string): number
	return script():askInt(title, prompt)
end

--- Asks for a decimal number.
function ui.askDouble(title: string, prompt: string): number
	return script():askDouble(title, prompt)
end

--- Asks for an address in the current program.
function ui.askAddress(title: string, prompt: string, default: string?)
	if default ~= nil then
		return script():askAddress(title, prompt, default)
	end
	return script():askAddress(title, prompt)
end

--- Asks a yes/no question.
function ui.askYesNo(title: string, prompt: string): boolean
	return script():askYesNo(title, prompt)
end

--- Asks the user to pick one of `choices` (a Luau array).
function ui.askChoice(title: string, prompt: string, choices: { any }, default: any?)
	local list = java.new(java.import("java.util.ArrayList"))
	for _, choice in choices do
		list:add(choice)
	end
	return script():askChoice(title, prompt, list, default ~= nil and default or choices[1])
end

--- Asks for a byte pattern, written as hex ("AA BB 00 1C"). Returns a Luau array
--- of numbers in 0..255, which is what @ghidra/memory and @ghidra/search take.
function ui.askBytes(title: string, prompt: string): { number }
	local raw = script():askBytes(title, prompt)
	local out = table.create(#raw)
	for index = 1, #raw do
		out[index] = raw[index] % 256
	end
	return out
end

--- Asks for an existing file. Returns a java.io.File.
function ui.askFile(title: string, approveLabel: string?)
	return script():askFile(title, approveLabel or "OK")
end

--- Asks for a directory. Returns a java.io.File.
function ui.askDirectory(title: string, approveLabel: string?)
	return script():askDirectory(title, approveLabel or "OK")
end

--- Asks the user to pick a project folder. Returns a DomainFolder.
function ui.askProjectFolder(prompt: string)
	return script():askProjectFolder(prompt)
end

--- Asks the user to pick a program from the project. Returns the open Program,
--- which the caller owns: give it back with `project.close(program)`.
function ui.askProgram(title: string)
	return script():askProgram(title)
end

--- Asks the user to pick a file from the project. Returns a DomainFile.
function ui.askDomainFile(title: string)
	return script():askDomainFile(title)
end

--- Asks the user to pick a processor language. Returns a LanguageCompilerSpecPair.
function ui.askLanguage(title: string, approveLabel: string?)
	return script():askLanguage(title, approveLabel or "OK")
end

local VALUE_KINDS = {
	string = "defineString",
	int = "defineInt",
	long = "defineLong",
	double = "defineDouble",
	boolean = "defineBoolean",
	file = "defineFile",
	directory = "defineDirectory",
	program = "defineProgram",
	address = "defineAddress",
	language = "defineLanguage",
	projectFile = "defineProjectFile",
	projectFolder = "defineProjectFolder",
}

local VALUE_READERS = {
	string = "getString",
	int = "getInt",
	long = "getLong",
	double = "getDouble",
	boolean = "getBoolean",
	file = "getFile",
	directory = "getFile",
	address = "getAddress",
	language = "getLanguage",
	choice = "getChoice",
	projectFile = "getProjectFile",
	projectFolder = "getProjectFolder",
}

--- Asks for several values in one dialog, instead of one prompt after another.
---
--- Fields are `{ name, kind, default?, choices? }`, where `kind` is one of
--- `string`, `int`, `long`, `double`, `boolean`, `file`, `directory`, `address`,
--- `language`, `choice`, `program`, `projectFile`, or `projectFolder`. A field
--- with `choices` is a choice regardless of its kind.
---
--- Returns a table keyed by field name. A field the user left empty is nil.
--- Headless runs answer each field from the script's .properties file, keyed by
--- the dialog title and the field name, the same way single prompts are.
---
---     local answers = ui.askValues("Report options", {
---         { name = "Name", kind = "string" },
---         { name = "Max Results", kind = "int", default = 100 },
---         { name = "Priority", kind = "choice", choices = { "Low", "High" } },
---     })
---     print(answers.Name, answers["Max Results"], answers.Priority)
function ui.askValues(title: string, fields: { any }, prompt: string?): { [string]: any }
	local ValuesMap = internal.classes["ghidra.features.base.values.GhidraValuesMap"]
	local values = ValuesMap()
	local String = java.import("java.lang.String")

	for _, field in fields do
		local name = field.name
		if name == nil then
			error("every askValues field needs a name", 2)
		end
		if field.choices ~= nil then
			local rest = java.array(String, math.max(#field.choices - 1, 0))
			for index = 2, #field.choices do
				rest[index - 1] = field.choices[index]
			end
			values:defineChoice(name, field.default or field.choices[1], rest)
			continue
		end
		local kind = field.kind or "string"
		local define = VALUE_KINDS[kind]
		if define == nil then
			error(`unknown askValues kind '{kind}' for field '{name}'`, 2)
		end
		-- Indexing a Java value with a method name yields a bound call, so the
		-- receiver is already captured.
		if field.default ~= nil then
			values[define](name, field.default)
		else
			values[define](name)
		end
	end

	local answered = script():askValues(title, prompt, values)

	local out = {}
	for _, field in fields do
		local kind = if field.choices ~= nil then "choice" else (field.kind or "string")
		if not answered:hasValue(field.name) then
			continue
		end
		if kind == "program" then
			-- A program comes back borrowed: the caller gives it back with
			-- project.close(program).
			out[field.name] = answered:getProgram(field.name, script(),
				internal.context():getTool(), true)
			continue
		end
		local read = VALUE_READERS[kind]
		if read ~= nil then
			out[field.name] = answered[read](field.name)
		end
	end
	return out
end

--- Shows a message and waits for the user to dismiss it. Prints instead when
--- there is no GUI, so a headless run is not left waiting on nobody.
function ui.popup(message: string)
	if internal.context():isHeadless() then
		internal.context():println(message)
		return
	end
	script():popup(message)
end

--- Moves the listing cursor. Accepts an Address, a Function, or a Symbol.
function ui.goTo(target): boolean
	return script():goTo(target)
end

--- Selects an address set in the listing. Does nothing headless.
function ui.setSelection(set)
	local script = script()
	if internal.context():isHeadless() then
		return
	end
	local Selection = internal.classes["ghidra.program.util.ProgramSelection"]
	script:setCurrentSelection(if internal.hasMethod(set, "getNumAddressRanges")
		then Selection(set)
		else set)
end

--- Clears the listing selection. Does nothing headless.
function ui.clearSelection()
	ui.setSelection(require("@ghidra/addresses").empty())
end

--- Shows a message in the tool's status area.
function ui.status(message: string)
	internal.context():setStatus(message)
end

return ui

-- The Ghidra project: its folders, its files, and the programs inside them.
--
--     local project = require("@ghidra/project")
--
--     for program in project.programs() do
--         print(program.name, program.functionCount)
--     end
--
-- A script that works across a whole project -- rename everything under a
-- folder, run an analysis over every binary, collect a report -- has to borrow
-- each program from its file and give it back afterwards, and give back the one
-- that raised too. `programs` and `withProgram` do that; the rest of the module
-- is the folder and file tree they walk.

local internal = require("@ghidra/internal/host")

local project = {}

local function script()
	return internal.context():getScript()
end

local function classes()
	return internal.classes
end

--- The Project this script is running in, raising when there is none -- a
--- console attached to no project, or a test harness.
function project.current()
	local state = script():getState()
	local value = state ~= nil and state:getProject() or nil
	if value == nil then
		error("no project is open", 3)
	end
	return value
end

--- The Project, or nil when there is none.
function project.tryCurrent()
	local state = script():getState()
	return state ~= nil and state:getProject() or nil
end

--- The project's name.
function project.name(): string
	return project.current():getName()
end

--- The root DomainFolder.
function project.root()
	return project.current():getProjectData():getRootFolder()
end

--- A folder by project path ("/", "/malware/samples"), or nil when there is no
--- such folder.
function project.folder(path: string?)
	if path == nil or path == "" or path == "/" then
		return project.root()
	end
	return project.current():getProjectData():getFolder(path)
end

--- Iterates every folder under `folder` (the root by default), including it.
function project.folders(folder)
	local ProjectDataUtils = classes()["ghidra.framework.model.ProjectDataUtils"]
	return internal.iterate(ProjectDataUtils:descendantFolders(folder or project.root()))
end

--- Iterates every file under `folder` (the root by default), at any depth.
function project.files(folder)
	local ProjectDataUtils = classes()["ghidra.framework.model.ProjectDataUtils"]
	return internal.iterate(ProjectDataUtils:descendantFiles(folder or project.root()))
end

--- True when a DomainFile holds a Program rather than a data type archive or
--- anything else the project can store.
function project.isProgram(file): boolean
	local Handler = classes()["ghidra.program.database.ProgramContentHandler"]
	return file:getContentType() == Handler.PROGRAM_CONTENT_TYPE
end

--- True when a versioned file cannot be opened for writing because nobody has
--- checked it out.
local function isLocked(file): boolean
	return file:isVersioned() and not file:isCheckedOut()
end

--- Opens the program in a DomainFile. The caller owns it and must call
--- `project.close(program)`; prefer `withProgram` or `programs`, which do that
--- even when the body raises.
---
--- Options: `upgrade` to upgrade an older database (default true), `readOnly`
--- to open a copy nothing can write back (default false).
function project.open(file, options: { upgrade: boolean?, readOnly: boolean? }?)
	local settings = options or {}
	local consumer = script()
	local monitor = internal.context():getMonitor()
	if settings.readOnly then
		return file:getReadOnlyDomainObject(consumer, -1, monitor)
	end
	return file:getDomainObject(consumer, settings.upgrade ~= false, false, monitor)
end

--- Gives a program back to the project. Every `open` needs one.
function project.close(program)
	program:release(script())
end

--- Opens the program in `file`, runs `body(program)`, and gives the program back
--- whether the body returns or raises. Returns whatever the body returned.
---
---     project.withProgram(file, function(program)
---         program:transaction("Comment", function() ... end)
---     end)
function project.withProgram(file, body: (any) -> any, options: { upgrade: boolean?, readOnly: boolean? }?)
	local program = project.open(file, options)
	local ok, result = pcall(body, program)
	project.close(program)
	if not ok then
		error(result, 0)
	end
	return result
end

--- Iterates every program in the project, or under `folder`, opening each one
--- and giving it back before moving on. Files that are versioned but not checked
--- out are skipped, since nothing may write to them.
---
--- The program is only valid inside the loop body: it is released as soon as the
--- iterator moves on.
---
---     for program, file in project.programs() do
---         print(file:getPathname(), program.functionCount)
---     end
function project.programs(folder, options: { upgrade: boolean?, readOnly: boolean?, includeLocked: boolean? }?)
	local settings = options or {}
	local step = project.files(folder)
	local current = nil

	return function()
		if current ~= nil then
			project.close(current)
			current = nil
		end
		while true do
			local file = step()
			if file == nil then
				return nil
			end
			if not project.isProgram(file) then
				continue
			end
			if isLocked(file) and not settings.includeLocked then
				continue
			end
			local ok, program = pcall(project.open, file, settings)
			if not ok then
				internal.context():printerr(
					`skipping {file:getPathname()}: {tostring(program)}`)
				continue
			end
			current = program
			return program, file
		end
	end
end

--- Saves a program that was opened from the project.
---
--- This cannot save the program the script itself is running against: the tool
--- holds it open with a transaction, and the save fails with "unable to lock due
--- to active transaction". A script that walks the project should skip the open
--- program, or be run with none open.
function project.save(program, comment: string?)
	program:save(comment or "Script", internal.context():getMonitor())
end

--- The DomainFile a program came from, or nil for one that was never saved.
function project.fileOf(program)
	return program:getDomainFile()
end

return project

-- The project: folders, files, and the programs inside them.
local t = require("@test")
local project = require("@ghidra/project")

-- The suite runs against a program that was never saved to a project, which is
-- the state a console attached to no project is in too.
t.assertEqual(project.tryCurrent(), nil, "project.tryCurrent is nil without a project")

local raised = pcall(function()
	return project.current()
end)
t.assertTrue(not raised, "project.current raises without a project")

local rootRaised = pcall(function()
	return project.root()
end)
t.assertTrue(not rootRaised, "so does anything that needs the project data")

-- Every program answers with a file, even one that was never saved to a project.
t.assertTrue(project.fileOf(require("@ghidra").program()) ~= nil, "project.fileOf")

t.finish("project")

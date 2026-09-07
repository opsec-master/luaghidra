-- java.extend: Luau properties and methods on Java classes.
local t = require("@test")

java.extend("java.util.ArrayList", {
	properties = {
		count = {
			get = function(self)
				return self:size()
			end,
		},
	},
	methods = {
		addAll2 = function(self, values)
			for _, value in values do
				self:add(value)
			end
			return self
		end,
	},
})

local list = java.new(java.import("java.util.ArrayList"))
list:addAll2({ "a", "b", "c" })
t.assertEqual(list.count, 3, "extension property")
t.assertEqual(list:size(), 3, "extension method ran")

-- Extensions registered on an interface apply to implementations.
java.extend("java.util.Collection", {
	properties = {
		firstOrNil = {
			get = function(self)
				return if self:isEmpty() then nil else self:iterator():next()
			end,
		},
	},
})
t.assertEqual(list.firstOrNil, "a", "extension inherited from an interface")

-- Java members always win, so an extension may not claim an existing name.
local ok, err = pcall(function()
	java.extend("java.util.ArrayList", { methods = { size = function() end } })
end)
t.assertTrue(not ok, "shadowing a Java method is rejected")
t.assertTrue(string.find(tostring(err), "shadow") ~= nil, "error explains the conflict")

t.finish("extend")

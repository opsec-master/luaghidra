-- Increments a global on load so the test can prove modules are cached.
_G.__counterLoads = (_G.__counterLoads or 0) + 1
return { value = _G.__counterLoads }

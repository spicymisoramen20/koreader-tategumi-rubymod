-- Set search path for `require()`.
package.path =
    "common/?.lua;frontend/?.lua;plugins/exporter.koplugin/?.lua;" ..
    package.path
-- Our win32 package ships Lua C modules as `libs/libkoreader-*.so` (MinGW MODULE
-- with a forced .so suffix). LuaJIT's default Windows cpath only looks for `.dll`.
package.cpath =
    "?.so;common/?.so;common/?.dll;/usr/lib/lua/?.so;" ..
    package.cpath
-- Setup `ffi.load` override and 'loadlib' helper.
require("ffi/loadlib")

-- Put functions in this file to use them in several other scripts.
-- To get access to the functions, you need to put:
-- require "my_directory.my_file"
-- in any script using the functions.
local sformat 	= string.format

logger = {}

logger.info = function(fmt, ...)
	print(sformat(fmt, ...))
end

logger.warn = function(fmt, ...)
	warn(sformat(fmt, ...))
end

logger.err = function(fmt, ...)
	error(sformat(fmt, ...))
end

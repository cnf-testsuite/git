require "totem"
require "colorize"
require "log"
require "file_utils"
require "../constants.cr"

def tools_path
  current_path = File.dirname(File.real_path(PROGRAM_NAME))
  "#{current_path}/tools"
end


def stdout_info(msg)
  puts msg
end

def stdout_success(msg)
  puts msg.colorize(:green)
end

def stdout_warning(msg)
  puts msg.colorize(:yellow)
end

def stdout_failure(msg)
  puts msg.colorize(:red)
end
# RubyLLM 2 owns persisted tool calls and their migrated table. Naming
# `ActiveRecord::Base` first runs the railtie hook that defines it -- see model.rb.
ActiveRecord::Base
ToolCall = RubyLLM::ActiveRecord::ToolCall

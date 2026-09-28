# RubyLLM 2 owns the registry model and its migrated table. Its railtie
# requires the class inside an `on_load(:active_record)` hook, so naming
# `ActiveRecord::Base` first runs that hook: without it a process that has
# not touched a record yet (`rake eval:estimate`) finds no such constant.
ActiveRecord::Base
Model = RubyLLM::ActiveRecord::Model

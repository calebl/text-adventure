# ActionController::Base rather than ::API: this app renders ERB for the
# browser interface. Under `load_defaults 8.0` that also turns on
# `protect_from_forgery`, so every form has to go through `form_with`.
class ApplicationController < ActionController::Base
end

# Pin npm packages by running ./bin/importmap
#
# Nothing here is downloaded or bundled: propshaft serves the files as they sit
# on disk, digested, and the browser's own module loader resolves these names.
# There is no `package.json` in this repo and there is not meant to be -- see
# AGENTS.md, "The browser interface".

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
pin "bootstrap", to: "bootstrap.bundle.min.js"

# CodeMirror - Use unpkg instead of jsdelivr (which might be blocked by CSP)
pin "codemirror", to: "https://unpkg.com/codemirror@5.65.13/lib/codemirror.js", preload: true
pin "codemirror/mode/sql/sql", to: "https://unpkg.com/codemirror@5.65.13/mode/sql/sql.js", preload: true
pin "codemirror/addon/edit/matchbrackets", to: "https://unpkg.com/codemirror@5.65.13/addon/edit/matchbrackets.js", preload: true
pin "codemirror/addon/edit/closebrackets", to: "https://unpkg.com/codemirror@5.65.13/addon/edit/closebrackets.js", preload: true
pin "codemirror/addon/display/placeholder", to: "https://unpkg.com/codemirror@5.65.13/addon/display/placeholder.js", preload: true

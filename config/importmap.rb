# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/helpers", under: "helpers"
pin "sortablejs" # @1.15.6
pin "chartkick", to: "chartkick.js", preload: true
# Use jspm.io for ES module compatible versions
pin "jquery", to: "https://ga.jspm.io/npm:jquery@3.7.1/dist/jquery.js", preload: true
# Select2 from jsdelivr expects jQuery to be available globally
pin "select2", to: "https://cdn.jsdelivr.net/npm/select2@4.0.13/dist/js/select2.min.js", preload: true
pin "choices.js", to: "https://cdn.jsdelivr.net/npm/choices.js@10.2.0/+esm", preload: true

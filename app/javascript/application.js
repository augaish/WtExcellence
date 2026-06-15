// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "chartkick"

// Import jQuery shim first to ensure it's available globally
import "helpers/select2_shim"

// Import Select2 which depends on jQuery being available globally
import "select2"

// Global confirmation modal helper (sets window.showConfirmationModal)
import "helpers/confirmation_modal"

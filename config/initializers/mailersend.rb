# MailerSend configuration
# 
# We use SMTP for email delivery (configured in environments/*.rb)
# API key is only needed if you want to use advanced features like:
# - Email verification API
# - Programmatic analytics
# - REST API for sending (instead of SMTP)
#
# For basic email sending via SMTP, this file is not required.
# The SMTP credentials in your .env file are sufficient.

# Uncomment below only if you need API features:
# if defined?(Mailersend)
#   Mailersend.configure do |config|
#     config.api_key = ENV["MAILERSEND_API_KEY"]
#   end
# end

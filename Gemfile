source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Bundle and transpile JavaScript [https://github.com/rails/jsbundling-rails]
gem "jsbundling-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
# Use Redis for Action Cable and Sidekiq
gem "redis", "~> 4.0"

# Background job processing
gem "sidekiq"

# Authentication
gem "devise"
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"

# External API integrations (from fsp-chron)
gem "aws-sdk-core"
gem "aws-sdk-s3"
gem "pdf-reader"  # For parsing BOM PDFs
gem "prawn"       # For generating summary PDFs
gem "prawn-table"
gem "matrix"      # Required for Prawn in Ruby 3.2+
gem "savon"       # NetSuite SOAP API
gem "mime-types"
gem "faraday", "~> 0.17"
gem "faraday_middleware", "0.14.0"
gem "faraday_middleware-aws-sigv4", "0.5.0"  # For AWS signed requests
gem "elasticsearch", "~> 7.4"  # For Project Sunrise API

# Google APIs for service account email sending
gem 'google-apis-gmail_v1', '~> 0.1'

# Error tracking
gem "sentry-ruby"
gem "sentry-rails"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # RSpec testing framework
  gem "rspec-rails", "~> 6.0"
  gem "factory_bot_rails"
  gem "faker"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Code coverage
  gem "simplecov", require: false
  gem "simplecov-json", require: false

  # Testing helpers
  gem "shoulda-matchers", "~> 5.0"
  gem "webmock"
  gem "vcr"
  gem "database_cleaner-active_record"
end

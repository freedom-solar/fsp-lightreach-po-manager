# Sidekiq logs at INFO to stdout by default, which clutters test output (e.g. the
# "Sidekiq connecting to Redis" boot line). Gate it to match the Rails log level so
# the test environment stays quiet; other environments keep their normal logging.
Sidekiq.configure_client do |config|
  config.logger.level = Rails.logger.level
end

Sidekiq.configure_server do |config|
  config.logger.level = Rails.logger.level
end

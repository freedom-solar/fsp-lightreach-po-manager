namespace :elasticsearch do
  desc "Test Elasticsearch connection and query"
  task test: :environment do
    puts "Testing Elasticsearch connection..."

    begin
      # Test basic connectivity
      es = ElasticSearchSunrise.new
      puts "✓ ElasticSearchSunrise initialized successfully"

      # Try a simple search
      puts "\nTesting a simple project search..."

      # Search for a known project ID from the screenshot (119847)
      project_id = '119847'
      result = ProjectSunriseApi.get_project(project_id)

      if result && result['success']
        data = result['data']
        puts "✓ Successfully fetched project #{project_id}"
        puts "  Project name: #{data['name']}"
        puts "  Lender: #{data.dig('fields', 'lender')}"
      else
        puts "✗ Could not fetch project #{project_id}"
      end

      puts "\n✓ Elasticsearch is working correctly!"

    rescue StandardError => e
      puts "\n✗ Elasticsearch test failed"
      puts "  Error: #{e.class} - #{e.message}"
      puts "\n  Backtrace:"
      puts e.backtrace.first(5).map { |line| "    #{line}" }.join("\n")

      if e.message.include?('region')
        puts "\n  ⚠ AWS region issue detected."
        puts "    Make sure AWS_REGION environment variable is set:"
        puts "    export AWS_REGION=us-west-2"
      elsif e.message.include?('credentials')
        puts "\n  ⚠ AWS credentials issue detected."
        puts "    Make sure these are set in Rails credentials:"
        puts "    - aws_key_id"
        puts "    - aws_secret_key"
        puts "    - elastic_search_url"
      end
    end
  end
end

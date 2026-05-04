require_relative 'elastic_search_sunrise'

class ProjectSunriseApi
    # Custom exception for API errors with context
    class ApiError < StandardError
        attr_reader :status_code, :url, :response_body

        def initialize(message, status_code: nil, url: nil, response_body: nil)
            @status_code = status_code
            @url = url
            @response_body = response_body
            super(message)
        end
    end

    # @@v2_root = Rails.application.credentials.dig(:PROJECT_SUNRISE, :ROOT_V2_DEV)
    # @@robot_user = Rails.application.credentials.dig(:PROJECT_SUNRISE, :USER_ID_DEV)
    # @@portal_id = '21083553'

    # if Rails.env.production?
    @@v2_root = Rails.application.credentials.dig(:PROJECT_SUNRISE, :ROOT_V2)
    @@robot_user = Rails.application.credentials.dig(:PROJECT_SUNRISE, :USER_ID)
    @@portal_id = '6994400'
    # end

    @@api_key = Rails.application.credentials.dig(:PROJECT_SUNRISE, :API_KEY)
    @@org_id = Rails.application.credentials.dig(:PROJECT_SUNRISE, :ORG_ID)

    @@v2_headers = { 'apiKey' => @@api_key }
    @@headers = { 'api-key' => @@api_key }
    require 'mime-types'

    def self.robot_user
        @@robot_user
    end

    def self.get_project_by_id(id, property_array = [])
        uri = URI("#{@@v2_root}/#{@@org_id}/projects/#{id}")
        fields = [
            'id',
            'name',
            'object_id',
            'primary_customer_id',
            'customers',
            'customers.fields'
        ]
        property_array.each do |property|
            fields << "fields.#{property}"
        end
        params = { fields: fields.join(','), **@@v2_headers }
        uri.query = URI.encode_www_form(params)
        response = HttpVerb.get(uri)
        response_body = parse_response(response, url: uri.to_s)
        response_body['data']['fields'] ||= {}
        result = {}

        if response_body['status'] != 'success'
            result['id'] = nil
            result['success'] = false
            property_array.map { |property| result[property] = nil }
        else
            fields = response_body['data']['fields']
            result['id'] = id
            result['deal_id'] = response_body['data']['object_id']
            result['success'] = true

            property_array.map do |property|
                is_deal_field = fields[property] != '' && fields[property]

                if is_deal_field
                    result[property] = fields[property]
                else
                    primary_customer_id = response_body['data']['primary_customer_id']
                    contacts = response_body['data']['customers']
                    contacts.select! { |contact| contact['_id'] == primary_customer_id } if primary_customer_id
                    primary_contact = contacts.first || { 'fields' => [] }
                    contact_fields = primary_contact['fields']
                    result[property] = contact_fields[property]
                end
            end
        end

        result
    end

    # PREFERRED: Returns raw API response with nested structure.
    # Use this method for new code - it preserves the native API format.
    #
    # Returns:
    #   {
    #     'success' => true/false,
    #     'data' => {
    #       '_id' => '...',
    #       'fields' => { 'dealname' => '...', ... },
    #       'customers' => [{ 'fields' => { ... } }, ...],
    #       ...
    #     }
    #   }
    #
    # Example usage:
    #   result = ProjectSunriseApi.get_project(id, fields: ['fields.dealname', 'customers.fields'])
    #   dealname = result.dig('data', 'fields', 'dealname')
    def self.get_project(id, fields: [])
        uri = URI("#{@@v2_root}/#{@@org_id}/projects/#{id}")
        default_fields = [
            'id',
            'name',
            'object_id',
            'primary_customer_id',
            'customers',
            'customers.fields'
        ]

        all_fields = fields + default_fields
        params = { fields: all_fields.join(','), **@@v2_headers }
        uri.query = URI.encode_www_form(params)
        response = HttpVerb.get(uri)
        response_body = parse_response(response, url: uri.to_s)

        return { 'success' => false, 'data' => nil } if response_body['status'] != 'success'

        {
            'success' => true,
            'data' => response_body['data']
        }
    end

    # DEBUG/TESTING ONLY: Fetches all fields for a project without filtering.
    # Not recommended for production use due to payload size.
    # For production code, use get_project() with specific fields.
    def self.get_project_by_id_all_fields_v2(id)
        uri = URI("#{@@v2_root}/#{@@org_id}/projects/#{id}")
        params = { apiKey: @@api_key, fields: [] } # apiKey stays in query params
        uri.query = URI.encode_www_form(params)

        headers = {} # This goes as a header
        response = HttpVerb.get(uri, headers: headers)
        response_body = parse_response(response, url: uri.to_s)

        return { 'id' => nil, 'success' => false } if response_body['status'] != 'success'

        response_body['data']
    end

    def self.search_customers(search:, fields: [])
        uri = URI("#{@@v2_root}/#{@@org_id}/customers")
        params = {
            **@@v2_headers,
            search: search,
            fields: fields.join(',')
        }
        uri.query = URI.encode_www_form(params)
        response = HttpVerb.get(uri)
        response_body = parse_response(response, url: uri.to_s)

        return { 'success' => false, 'data' => nil } unless response_body['status']

        {
            'success' => true,
            'count' => response_body.dig('data', 'count'),
            'items' => response_body.dig('data', 'items') || []
        }
    end

    def self.get_incomplete_tasks(task_name, project_id: nil, project_id_array: nil, return_project_ids: false)
        project_ids = project_id_array || [project_id].compact

        # If no project filter provided, fall back to Elasticsearch
        # The API doesn't handle broad task searches well (502 errors)
        if project_ids.empty?
            es = ElasticSearchSunrise.new
            return es.get_incomplete_tasks(task_name, return_project_ids: return_project_ids)
        end

        results = []
        project_ids.each do |pid|
            tasks = get_all_tasks(pid)
            incomplete_tasks = tasks&.select { |t| t['name'] == task_name && !t['is_complete'] } || []
            results.concat(incomplete_tasks)
        end

        if return_project_ids
            results.map { |task| task['project_id'] }.uniq
        else
            results
        end
    end

    def self.get_complete_tasks(task_name, project_id: nil, project_id_array: nil, return_project_ids: false)
        project_ids = project_id_array || [project_id].compact

        # If no project filter provided, fall back to Elasticsearch
        # The API doesn't handle broad task searches well (502 errors)
        if project_ids.empty?
            es = ElasticSearchSunrise.new
            return es.get_complete_tasks(task_name, return_project_ids: return_project_ids)
        end

        results = []
        project_ids.each do |pid|
            tasks = get_all_tasks(pid)
            complete_tasks = tasks&.select { |t| t['name'] == task_name && t['is_complete'] } || []
            results.concat(complete_tasks)
        end

        if return_project_ids
            results.map { |task| task['project_id'] }.uniq
        else
            results
        end
    end

    def self.get_project_property(project_id, property)
        project_props = get_project_by_id(project_id, [property])
        project_props[property]
    end

    def self.get_projects_bulk(project_ids, fields: [])
        uri = URI("#{@@v2_root}/#{@@org_id}/projects")
        params = {
            **@@v2_headers,
            documentIds: project_ids.join(','),
            fields: fields.join(','),
            size: project_ids.length
        }
        uri.query = URI.encode_www_form(params)
        response = HttpVerb.get(uri)
        response_body = parse_response(response, url: uri.to_s)

        return { 'success' => false, 'data' => nil } unless response_body['status']

        {
            'success' => true,
            'count' => response_body.dig('data', 'count'),
            'items' => response_body.dig('data', 'items') || []
        }
    end

    def self.recalculate_tasks(project_id)
        uri = URI("#{@@v2_root}/#{@@org_id}/projects/#{project_id}/generate-tasks?apiKey=#{@@api_key}")
        body = { process: 'generate/recalculate' }
        response = HttpVerb.post(uri, body, headers: @@v2_headers)
        parse_response(response, url: uri.to_s)
    end

    def self.recalculate_critical_path(project_id)
        uri = URI("#{@@v2_root}/#{@@org_id}/critical-path/calculate?apiKey=#{@@api_key}")
        body = { projects: [project_id] }
        response = HttpVerb.post(uri, body, headers: @@v2_headers)
        parse_response(response, url: uri.to_s)
    end

    def self.upload_file_to_folder(
        project_id,
        path,
        file_name:,
        folder_name: nil,
        category_id: nil,
        content_type: nil,
        task_id: nil,
        task_group_id: nil,
        preserve_file: false,
        ignore_abort: false
    )
        folder_path = '/'
        missing_folder = false
        if folder_name
            files = ProjectSunriseApi.get_files_v2(project_id)
            should_abort = files.detect do |file|
                file['category_id'] == category_id && file['task_id'] == task_id
            end.present?

            folder_hash = files.detect { |file| file['name'] == folder_name }
            missing_folder = folder_hash.nil?
            folder_path << folder_hash['s3_name'] << '/' if folder_hash
        end

        puts "ABORTING: #{file_name} already exists in #{folder_name}" if should_abort && !ignore_abort
        return nil if should_abort && !ignore_abort

        puts "ABORTING: #{folder_name} does not exist" if missing_folder

        uri = URI("#{@@v2_root}/#{@@org_id}/projects/#{project_id}/files/getUploadSignedUrl")
        uri.query = URI.encode_www_form(@@v2_headers)
        path = Rails.root.join('storage', path)
        content_type ||= MIME::Types.type_for(path)&.first&.content_type || 'application/octet-stream'

        body = {
            path: folder_path,
            type: content_type,
            name: file_name
        }
        body[:category_id] = category_id if category_id
        body[:task_id] = task_id if task_id
        body[:task_group_id] = task_group_id if task_group_id

        response = HttpVerb.post(uri, body, headers: @@headers)
        response_body = parse_response(response, url: uri.to_s)
        return nil if response_body['status'] == 'fail'

        aws_uri = URI(response_body['data']['url'])

        response = HttpVerb.put_file(aws_uri, path, content_type:)
        File.delete(path) unless preserve_file
        response.body
    end

    def self.get_all_tasks(project_id)
        fields = %w[
            project_id
            name
            is_complete
            completed_at
            is_ready
            ready_at
            on_hold
            owner
            user_id
            team_id
            completed_by
            fsp_properties
            fields
        ]
        uri = URI("#{@@v2_root}/#{@@org_id}/tasks")
        additional_params = { fields: fields.join(','), projectId: project_id, size: 9999 }
        params = @@v2_headers.merge(additional_params)
        uri.query = URI.encode_www_form(params)
        response = HttpVerb.get(uri)
        parse_response(response, url: uri.to_s)['data']['items']
    end

    def self.get_task_status(project_id, task_name_array, fallback = false)
        tasks = get_all_tasks(project_id)
        result = {}
        task_name_array.map do |task_name|
            task = tasks.detect { |task_result| task_result['name'] == task_name }
            result[task_name] = if task
                                    task['is_complete']
                                else
                                    fallback
                                end
        end
        result
    end

    def self.get_task(task_id, fields: nil)
        fields ||= %w[name is_complete project_id fields fsp_properties]
        uri = URI("#{@@v2_root}/#{@@org_id}/tasks/#{task_id}")
        params = { **@@v2_headers, fields: fields.join(',') }
        uri.query = URI.encode_www_form(params)
        response = HttpVerb.get(uri)
        response_body = parse_response(response, url: uri.to_s)

        return nil if response_body['status'] != 'success'

        response_body['data']
    end

    def self.get_task_date(project_id, task_name_array)
        tasks = get_all_tasks(project_id)
        result = {}
        task_name_array.map do |task_name|
            result[task_name] = nil
            task = tasks.detect { |task_result| task_result['name'] == task_name }
            result[task_name] = Time.at(task['completed_at'] / 1000) if task && !task['completed_at'].nil?
        end
        result
    end

    def self.get_task_id(project_id, task_name)
        all_tasks = ProjectSunriseApi.get_all_tasks(project_id)
        task = all_tasks.select { |t| t['name'] == task_name }

        if task.blank?
            nil
        else
            task.first['_id']
        end
    end

    def self.check_off_task(project_id, task_name, user_id: @@robot_user, is_complete: true)
        task_id = get_task_id(project_id, task_name)

        return nil unless task_id.present?

        uri = URI("#{@@v2_root}/#{@@org_id}/projects/#{project_id}/tasks/#{task_id}")
        uri.query = URI.encode_www_form(@@v2_headers)
        body = {
            "user_id": user_id,
            "is_complete": is_complete
        }
        response = HttpVerb.patch(uri, body, headers: @@v2_headers)
        recalculate_critical_path(project_id)
        response.body
    end

    def self.update_project(project_id, props, customer_id: nil, ignore_hubspot_errors: false)
        uri = URI("#{@@v2_root}/#{@@org_id}/projects/#{project_id}")
        headers = @@v2_headers
        headers[:ignoreHubspotError] = ignore_hubspot_errors if ignore_hubspot_errors
        uri.query = URI.encode_www_form(@@v2_headers)
        body = { fields: props }
        body[:customerId] = customer_id if customer_id
        response = HttpVerb.patch(uri, body)
        puts response.body if response.code&.to_i != 204
        response.code&.to_i == 204
    end

    def self.update_filters(project_id)
        submittals = [
            'Submit Architectural Improvement Request',
            'Submit Interconnection Application',
            'Submit Permit Application',
            'Submit Utility Rebate Application',
            'Determine Permitting Requirements'
        ]

        approvals = [
            'Upload Architectural Improvement Request Approval',
            'Upload Architectural Improvement Request Approval',
            'Upload Permit Application Approval',
            'Upload Utility Rebate Application Approval'
        ]

        submittal_statuses = get_task_status(project_id, submittals, true)
        approval_statuses = get_task_status(project_id, approvals, true)

        updates = {
            'pending_interconnection_submittal_only' => 'No',
            'pending_interconnection_approval_only' => 'No',
            'pending_h_o_a_approval_only' => 'No',
            'pending_permit_approval_only' => 'No',
            'pending_rebate_approval_only' => 'No'
        }

        if !submittal_statuses['Submit Interconnection Application'] &&
           submittal_statuses['Determine Permitting Requirements'] &&
           approval_statuses['Upload Architectural Improvement Request Approval'] &&
           approval_statuses['Upload Permit Application Approval'] &&
           approval_statuses['Upload Utility Rebate Application Approval']
            updates['pending_interconnection_submittal_only'] = 'Yes'
        end

        if !approval_statuses['Upload Interconnection Application Approval'] &&
           submittal_statuses['Determine Permitting Requirements'] &&
           submittal_statuses['Submit Interconnection Application'] &&
           approval_statuses['Upload Architectural Improvement Request Approval'] &&
           approval_statuses['Upload Permit Application Approval'] &&
           approval_statuses['Upload Utility Rebate Application Approval']
            updates['pending_interconnection_approval_only'] = 'Yes'
        end

        if !approval_statuses['Upload Architectural Improvement Request Approval'] &&
           submittal_statuses['Determine Permitting Requirements'] &&
           submittal_statuses['Submit Interconnection Application'] &&
           submittal_statuses['Submit Architectural Improvement Request'] &&
           approval_statuses['Upload Permit Application Approval'] &&
           approval_statuses['Upload Utility Rebate Application Approval']
            updates['pending_h_o_a_approval_only'] = 'Yes'

        end

        if approval_statuses['Upload Architectural Improvement Request Approval'] &&
           submittal_statuses['Determine Permitting Requirements'] &&
           !approval_statuses['Upload Permit Application Approval'] &&
           submittal_statuses['Submit Permit Application'] &&
           submittal_statuses['Submit Interconnection Application'] &&
           approval_statuses['Upload Utility Rebate Application Approval']
            updates['pending_permit_approval_only'] = 'Yes'
        end

        if approval_statuses['Upload Architectural Improvement Request Approval'] &&
           submittal_statuses['Determing Permitting Requirements'] &&
           approval_statuses['Upload Permit Application Approval'] &&
           submittal_statuses['Submit Interconnection Application'] &&
           submittal_statuses['Submit Utility Rebate Application'] &&
           !approval_statuses['Upload Utility Rebate Application Approval']
            updates['pending_rebate_approval_only'] = 'Yes'

        end

        update_project(project_id, updates)
    end

    def self.get_file_page(project_id, page_token)
        uri = URI("#{@@v2_root}/#{@@org_id}/projects/#{project_id}/files")
        headers = {}
        headers['nextPageToken'] = page_token if page_token
        uri.query = URI.encode_www_form(@@v2_headers.merge(headers))
        response = HttpVerb.get(uri)
        parse_response(response, url: uri.to_s)
    end

    def self.get_files_v2(project_id)
        results = []
        response_body = get_file_page(project_id, nil)
        results += response_body['data']['files']
        next_page_token = response_body['data']['nextPageToken']
        while next_page_token
            response_body = get_file_page(project_id, next_page_token)
            results += response_body['data']['files']
            next_page_token = response_body['data']['nextPageToken']
        end
        results.sort_by { |file| file['created_at'] }
    end

    def self.confirm_file(project_id, search)
        es = ElasticSearchSunrise.new(worker: 'ProjectSunriseApi')
        categories = es.get_categories(es.residential)
        category_id = categories[search]
        return false unless category_id

        files = get_files_v2(project_id)

        candidates = files.select do |file|
            category_id && file['category_id'] == category_id && !file['deleted']
        end

        candidates.length.positive?
    end

    def self.get_file(project_id, category_name, search: nil, include_all_files: false)
        categories = ElasticSearchSunrise.new.get_categories('BhpMj')
        category_id = categories[category_name]

        files = get_files_v2(project_id)
        files.reject! { |file| file['deleted'] }
        matching_files = files.select do |file|
            if category_id.present? && search.present?
                file['category_id'] == category_id && file['name'].include?(search)
            elsif category_id.present?
                file['category_id'] == category_id
            elsif search.present?
                file['name'].include?(search)
            else
                false
            end
        end

        if include_all_files
            matching_files.map { |file_metadata| get_file_from_aws(file_metadata) }
        else
            file_metadata = matching_files[-1]
            get_file_from_aws(file_metadata)
        end
    end

    def self.get_file_from_aws(file_metadata)
        result = { 'file' => nil, 'name' => nil, 'content_type' => nil }

        if file_metadata
            bucket_name = 'sunrise-files-prod'
            key = file_metadata['key']
            # type = file_metadata['type']
            name = file_metadata['name']

            # Configure S3 client with SSL options to handle certificate issues
            # Disable SSL verification in development to bypass CRL validation issues
            s3 = Aws::S3::Client.new(
                http_open_timeout: 15,
                http_read_timeout: 60,
                retry_limit: 3,
                ssl_verify_peer: false
            )

            tempfile = Tempfile.new
            tempfile.binmode

            s3.get_object({ bucket: bucket_name, key: }, target: tempfile)

            result['file'] = tempfile
            result['name'] = name
            result['id'] = file_metadata['_id']
            result['content_type'] = file_metadata['type']
            if result['content_type'].blank? || result['content_type'] == 'application/octet-stream'
                result['content_type'] = MIME::Types.type_for(name).first.content_type
            end
        end

        result
    end

    def self.create_task(project_id, name, department_id: 'BhpMj', user_id: '', team_id: '', owner: '')
        es = ElasticSearchSunrise.new
        template = es.get_task_template(name, department_id:)

        body = {
            name:,
            user_id:,
            team_id:,
            owner:,
            notes: '',
            due_date: Time.now.to_i * 1000,
            task_template_id: template['_id'],
            task_group_id: template.dig('_source', 'task_group_id')
        }
        uri = URI("#{@@v2_root}/#{@@org_id}/projects/#{project_id}/tasks?apiKey=#{@@api_key}")
        response = HttpVerb.post(uri, body, headers: @@v2_headers)
        parse_response(response, url: uri.to_s)
    rescue StandardError => e
        puts e
    end

    def self.create_pulse_note(project_id, text:, user_id: @@robot_user, task_name: nil, task_id: nil, created_at: nil)
        created_at ||= Time.now.to_i * 1000
        body = {
            text:,
            user_id:,
            created_at:
        }
        task_id ||= get_task_id(project_id, task_name) if task_name
        body[:task_id] = task_id if task_id
        uri = URI("#{@@v2_root}/#{@@org_id}/projects/#{project_id}/pulse?apiKey=#{@@api_key}")
        response = HttpVerb.post(uri, body, headers: @@v2_headers)
        response.body
    end

    def self.get_pulse_note(project_id)
        uri = URI("#{@@v2_root}/#{@@org_id}/projects/#{project_id}/pulse?apiKey=#{@@api_key}")
        response = HttpVerb.get(uri, headers: @@v2_headers)
        response.body
    end

    def self.hubspot_pulse_email(project_id, email)
        props = email['properties']
        es = ElasticSearchSunrise.new
        is_inbound = props['hs_email_direction'] == 'INCOMING_EMAIL'
        ticket_url = "<a href='https://app.hubspot.com/contacts/#{@@portal_id}/ticket/#{email['ticket_id']}' target='_blank'>#{email['ticket_id']}</a>"
        ticket_email_url = "<a href='https://app.hubspot.com/contacts/#{@@portal_id}/ticket/#{email['ticket_id']}?engagement=#{email['id']}' target='_blank'>#{email['id']}</a>"

        user_email = is_inbound ? props['hs_email_to_email'] : props['hs_email_sender_email']
        begin
            hubspot_user = HubSpot::Owner.find(props['hubspot_owner_id'])
        rescue JSON::ParserError
            hubspot_user = nil
        end
        user_email = hubspot_user['email'] if hubspot_user

        return unless user_email

        user = es.get_user(user_email)

        if props['hs_email_sender_email']
            from_email = props['hs_email_sender_email']
            from_name = "#{props['hs_email_from_firstname']} #{props['hs_email_from_lastname']}"
        elsif !is_inbound && user
            from_email = user['email']
            from_name = user['name']
        elsif !is_inbound && hubspot_user
            from_email = hubspot_user['email']
            from_name = "#{hubspot_user['firstName']} #{hubspot_user['lastName']}"
        elsif !is_inbound
            from_email = 'unknown@gofreedompower.com'
            from_name = 'Unknown'
        else
            from_email = email['contact_email']
            from_name = email['contact_name']
        end

        from = "#{from_name} [#{from_email}]"

        if props['hs_email_to_email']
            to_email = props['hs_email_to_email']
            to_name = "#{props['hs_email_to_firstname']} #{props['hs_email_to_lastname']}"
        elsif !is_inbound
            to_email = email['contact_email']
            to_name = email['contact_name']
        elsif is_inbound && hubspot_user
            to_email = hubspot_user['email']
            to_name = "#{hubspot_user['firstName']} #{hubspot_user['lastName']}"
        elsif is_inbound && user
            to_email = user['email']
            to_name = user['name']
        else
            to_email = 'unknown@gofreedompower.com'
            to_name = 'Unknown'
        end
        to = "#{to_name} [#{to_email}]"

        subject = props['hs_email_subject'] || 'Manually Logged HubSpot Email'

        user_id = @@robot_user
        user_id = user['id'] if user

        created_at = Time.parse(props['hs_timestamp']).to_i * 1000

        body = ''
        if email['ticket_name'].present?
            body += "Ticket: #{ticket_url}<br/>"
            body += "Ticket Email Link: #{ticket_email_url}<br/>"
            body += "Ticket Name: #{email['ticket_name']}<br/>"
            body += "Ticket Description: #{email['ticket_content']}<br/><br/>"
        end
        body += "Subject: #{subject}<br/>"
        body += "From: #{from}<br/>"
        body += "To: #{to}<br/><br/>"
        body += props['hs_email_text']&.gsub(/\n/, '<br/>') || ''

        if body.include?('wrote:')
            body = body.split('wrote:')[0]
            body_parts = body.split('On')
            body_parts.pop
            body = body_parts.join('')
        end

        if body.include?('This electronic communication (including any attached document)')
            body = body.split('This electronic communication (including any attached document)')[0]
        end

        source = {
            id: email['id'],
            created_at:,
            project_id:,
            title: email['properties']['hs_email_subject'],
            type: 'comments',
            subtype: 'hubspot_note',
            body:,
            organization_id: @@org_id,
            metadata: {
                user_id:
            }
        }

        search_source = source.slice(
            :id, :project_id
        )
        puts "Project ID: #{project_id}, Subject: #{subject}, Created At: #{Time.at(created_at / 1000).to_date}"
        puts '--------'
        puts "From: #{from}"
        puts "To: #{to}"
        puts "Subject: #{subject}"
        puts ''
        record_id = es.check_for_record(index: 'pulse', source: search_source)
        if record_id
            es.update(id: record_id, index: 'pulse', body: source)
        else
            es.client.index(index: 'pulse', body: source)
        end
    end

    def self.hubspot_pulse_call(project_id, call)
        props = call['properties']
        es = ElasticSearchSunrise.new
        ticket_url = "<a href='https://app.hubspot.com/contacts/#{@@portal_id}/ticket/#{call['ticket_id']}' target='_blank'>#{call['ticket_id']}</a>"
        ticket_call_url = "<a href='https://app.hubspot.com/contacts/#{@@portal_id}/ticket/#{call['ticket_id']}?engagement=#{call['id']}' target='_blank'>#{call['id']}</a>"

        begin
            hubspot_user = HubSpot::Owner.find(props['hubspot_owner_id'])
            user_name = "#{hubspot_user['firstName']} #{hubspot_user['lastName']}"
            user_email = hubspot_user['email']
        rescue JSON::ParserError
            user_name = ''
            user_email = ''
        end

        return unless user_email

        user = es.get_user(user_email)

        user_id = @@robot_user
        user_id = user['id'] if user

        is_inbound = props['hs_call_direction'] == 'INBOUND'
        created_at = Time.parse(props['hs_timestamp']).to_i * 1000

        if is_inbound
            from_name = call['contact_name']
            to_name = user_name
        else
            from_name = user_name
            to_name = call['contact_name']
        end

        from_number = props['hs_call_from_number']
        to_number = props['hs_call_to_number']

        from = from_name
        from << " [#{from_number}]" if from_number
        to = to_name
        to << " [#{to_number}]" if to_number

        body = ''
        if call['ticket_name'].present?
            body += "Ticket: #{ticket_url}<br/>"
            body += "Ticket Call Link: #{ticket_call_url}<br/>"
            body += "Ticket Name: #{call['ticket_name']}<br/>"
            body += "Ticket Description: #{call['ticket_content']}<br/><br/>"
        end
        body += "From: #{from}<br/>" if from.present?
        body += "To: #{to}<br/>" if to.present?
        body += "Title: #{props['hs_call_title']}<br/><br/>"
        body += props['hs_call_body']&.gsub(/\n/, '<br/>') || ''

        source = {
            id: call['id'],
            created_at:,
            project_id:,
            title: props['hs_call_title'],
            type: 'comments',
            subtype: 'hubspot_note',
            body:,
            organization_id: @@org_id,
            metadata: {
                user_id:
            }
        }

        search_source = source.slice(
            :id, :project_id
        )
        puts "CALL: Project ID: #{project_id}, Created At: #{Time.at(created_at / 1000).to_date}"
        puts '--------'

        record_id = es.check_for_record(index: 'pulse', source: search_source)
        if record_id
            es.update(id: record_id, index: 'pulse', body: source)
        else
            es.client.index(index: 'pulse', body: source)
        end
    end

    def self.hubspot_pulse_note(project_id, note)
        note_body = note['properties']['hs_note_body']
        return unless note_body && note_body.length > 5

        props = note['properties']
        es = ElasticSearchSunrise.new
        ticket_url = "<a href='https://app.hubspot.com/contacts/#{@@portal_id}/ticket/#{note['ticket_id']}' target='_blank'>#{note['ticket_id']}</a>"
        ticket_note_url = "<a href='https://app.hubspot.com/contacts/#{@@portal_id}/ticket/#{note['ticket_id']}?engagement=#{note['id']}' target='_blank'>#{note['id']}</a>"

        begin
            hubspot_user = HubSpot::Owner.find(props['hubspot_owner_id'])
            user_email = hubspot_user['email']
        rescue JSON::ParserError
            user_email = ''
        end

        return unless user_email

        user = es.get_user(user_email)
        user_id = @@robot_user
        user_id = user['id'] if user

        created_at = Time.parse(props['hs_timestamp']).to_i * 1000

        body = ''
        if note['ticket_name'].present?
            body += "Ticket: #{ticket_url}<br/>"
            body += "Ticket Note Link: #{ticket_note_url}<br/>"
            body += "Ticket Name: #{note['ticket_name']}<br/>"
            body += "Ticket Description: #{note['ticket_content']}<br/><br/>"
        end
        body += props['hs_note_body']&.gsub(/\n/, '<br/>') || ''

        source = {
            id: note['id'],
            created_at:,
            project_id:,
            title: 'HubSpot Note',
            type: 'comments',
            subtype: 'hubspot_note',
            body:,
            organization_id: @@org_id,
            metadata: {
                user_id:
            }
        }

        search_source = source.slice(
            :id, :project_id
        )
        puts "NOTE: Project ID: #{project_id}, Created At: #{Time.at(created_at / 1000).to_date}"
        puts '--------'

        record_id = es.check_for_record(index: 'pulse', source: search_source)
        if record_id
            es.update(id: record_id, index: 'pulse', body: source)
        else
            es.client.index(index: 'pulse', body: source)
        end
    end

    # Safe JSON parsing with error handling and logging
    def self.parse_response(response, url: nil)
        status_code = response.code.to_i
        body = response.body

        unless response.is_a?(Net::HTTPSuccess) || (200..299).cover?(status_code)
            log_api_error("HTTP #{status_code}", url:, status_code:, body:)
            raise ApiError.new(
                "Project Sunrise API returned HTTP #{status_code}",
                status_code:, url:, response_body: body&.truncate(500)
            )
        end

        JSON.parse(body)
    rescue JSON::ParserError => e
        log_api_error("Invalid JSON response", url:, status_code:, body:)
        raise ApiError.new(
            "Project Sunrise API returned invalid JSON: #{e.message}",
            status_code:, url:, response_body: body&.truncate(500)
        )
    end

    def self.log_api_error(message, url:, status_code:, body:)
        Rails.logger.error("[ProjectSunriseApi] #{message}")
        Rails.logger.error("  URL: #{url}")
        Rails.logger.error("  Status: #{status_code}")
        Rails.logger.error("  Response: #{body&.truncate(500)}")

        Sentry.capture_message(
            "ProjectSunriseApi error: #{message}",
            level: :error,
            extra: { url:, status_code:, response_body: body&.truncate(1000) }
        )
    end
end

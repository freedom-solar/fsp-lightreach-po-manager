module Netsuite
    # Handles Oauth 1.0 authentication workflow for Netsuite Suitetalk API and allows you to send requests
    # Example implementation:
    # @client = Netsuite::Client.new)
    # customer_metadata = @client.get("/record/v1/metadata-catalog/customer")

    # Client Class

    class Client
        attr_reader :headers, :signature, :consumer_key, :consumer_secret, :token_id, :token_secret

        MAX_AUTH_RETRIES = 2  # Original attempt + 1 retry

        def initialize(environment = :production)
            @environment = environment
            get_credentials(environment)
        end

        # Defining HTTP methods to be used for requests
        def get(path:, params: {})
            uri_string = "#{@root_url}#{path}"
            uri = URI(uri_string)
            uri.query = URI.encode_www_form(params)

            response = nil
            MAX_AUTH_RETRIES.times do |attempt|
                # Generate fresh headers (nonce/timestamp) for each attempt
                headers = Headers.new(url: uri_string, method: :GET, params:, credentials: @credentials).generate
                response = HttpVerb.get(uri, headers:, limit: 1)

                # Retry 401 errors with 10-second wait
                break unless response.code == '401' && attempt < MAX_AUTH_RETRIES - 1

                sleep_time = 10
                Rails.logger.warn "[NetSuite] 401 Unauthorized on GET #{path}, retrying in #{sleep_time}s"
                sleep(sleep_time)
            end

            unless response.is_a?(Net::HTTPSuccess)
                raise_netsuite_error(response, method: 'GET', path: path, params: params)
            end

            JSON.parse(response.body)
        end

        def post(path:, body: {}, params: {}, return_method: :id)
            uri_string = "#{@root_url}#{path}"
            uri = URI(uri_string)
            uri.query = URI.encode_www_form(params)

            response = nil
            MAX_AUTH_RETRIES.times do |attempt|
                headers = Headers.new(url: uri_string, method: :POST, params:, credentials: @credentials).generate
                response = HttpVerb.post(uri, body, headers:, limit: 1)

                break unless response.code == '401' && attempt < MAX_AUTH_RETRIES - 1

                sleep_time = 10
                Rails.logger.warn "[NetSuite] 401 Unauthorized on POST #{path}, retrying in #{sleep_time}s"
                sleep(sleep_time)
            end

            puts "Response: #{response.body}"
            JSON.parse(response.body) if return_method == :body
            response['Location'].split('/')[-1] if return_method == :id
        end

        def patch(path:, body: {}, params: {})
            uri_string = "#{@root_url}#{path}"
            uri = URI(uri_string)
            uri.query = URI.encode_www_form(params)

            response = nil
            MAX_AUTH_RETRIES.times do |attempt|
                headers = Headers.new(url: uri_string, method: :PATCH, params:, credentials: @credentials).generate
                headers['Prefer'] = 'transient.respondOnUpdate=true'
                response = HttpVerb.patch(uri, body, headers:, limit: 1)

                break unless response.code == '401' && attempt < MAX_AUTH_RETRIES - 1

                sleep_time = 10
                Rails.logger.warn "[NetSuite] 401 Unauthorized on PATCH #{path}, retrying in #{sleep_time}s"
                sleep(sleep_time)
            end

            response.body
        end

        def delete(path:)
            uri_string = "#{@root_url}#{path}"
            uri = URI(uri_string)

            response = nil
            MAX_AUTH_RETRIES.times do |attempt|
                headers = Headers.new(url: uri_string, method: :DELETE, params: {}, credentials: @credentials).generate
                response = HttpVerb.delete(uri, headers:, limit: 1)

                break unless response.code == '401' && attempt < MAX_AUTH_RETRIES - 1

                sleep_time = 10
                Rails.logger.warn "[NetSuite] 401 Unauthorized on DELETE #{path}, retrying in #{sleep_time}s"
                sleep(sleep_time)
            end

            response.body
        end

        # Defining simple crud actions

        def create_record(object:, body:, params: {})
            post(path: "/record/v1/#{object}", body:, params:)
        end

        def get_record(object:, id: nil, external_id: nil, params: {}, retry_on_401: true)
            path = "/record/v1/#{object}/#{id}"
            path = "/record/v1/#{object}/eid:#{external_id}" if external_id

            # Skip retries when just checking record type (e.g., checking if item is inventory item)
            if retry_on_401
                get(path:, params:)
            else
                # Make single request without retries
                uri_string = "#{@root_url}#{path}"
                uri = URI(uri_string)
                uri.query = URI.encode_www_form(params)

                headers = Headers.new(url: uri_string, method: :GET, params:, credentials: @credentials).generate
                response = HttpVerb.get(uri, headers:, limit: 1)

                unless response.is_a?(Net::HTTPSuccess)
                    raise_netsuite_error(response, method: 'GET', path: path, params: params)
                end

                JSON.parse(response.body)
            end
        end

        def list_records(object:, params: {})
            get(path: "/record/v1/#{object}", params:)
        end

        def update_record(object:, id:, body:, params: {})
            patch(path: "/record/v1/#{object}/#{id}", body:, params:)
        end

        def delete_record(object:, id: nil, external_id: nil)
            path = "/record/v1/#{object}/#{id}"
            path = "/record/v1/#{object}/eid:#{external_id}" if external_id
            delete(path:)
        end

        # Filters and queries

        def query(object:, query:)
            get(path: "/record/v1/#{object}", params: { 'q' => query })
        end

        def suiteql(query:, limit: 1000, offset: 0)
            uri_string = "#{@root_url}/query/v1/suiteql"
            uri = URI(uri_string)
            params = { limit:, offset: }
            uri.query = URI.encode_www_form(params)
            headers = Headers.new(url: uri_string, method: :POST, params:, credentials: @credentials).generate
            headers['Prefer'] = 'transient'
            response = HttpVerb.post(uri, { q: query }, headers:, limit: 1)
            JSON.parse(response.body)
        end

        def get_credentials(environment)
            @credentials = Rails.application.credentials.netsuite[environment]
            @service = @credentials[:rest_services]
            @account_id_url = @credentials[:account_id_url]
            @root_url = "https://#{@account_id_url}.#{@service}.netsuite.com/services/rest"
        end

        # Call a RESTlet by its script and deploy IDs
        def call_restlet(script_id:, deploy_id:, params: {}, method: :get)
            restlet_url = "https://#{@account_id_url}.restlets.api.netsuite.com/app/site/hosting/restlet.nl"
            params_with_ids = params.merge(script: script_id, deploy: deploy_id)

            uri = URI(restlet_url)
            uri.query = URI.encode_www_form(params_with_ids)

            Rails.logger.info "[NetSuite RESTlet] Environment: #{@environment}"
            Rails.logger.info "[NetSuite RESTlet] Account ID: #{@account_id_url}"
            Rails.logger.info "[NetSuite RESTlet] Full URL: #{uri}"
            Rails.logger.info "[NetSuite RESTlet] Script ID: #{script_id}, Deploy ID: #{deploy_id}"

            headers = Headers.new(
                url: restlet_url,
                method: method.to_s.upcase.to_sym,
                params: params_with_ids,
                credentials: @credentials
            ).generate

            response = if method == :get
                           HttpVerb.get(uri, headers:, limit: 1)
                       else
                           HttpVerb.post(uri, params, headers:, limit: 1)
                       end

            Rails.logger.info "[NetSuite RESTlet] Response code: #{response.code}"
            Rails.logger.info "[NetSuite RESTlet] Response body: #{response.body}"

            JSON.parse(response.body)
        end

        private

        def raise_netsuite_error(response, method:, path:, params: {}, body: nil)
            Sentry.set_context('netsuite_request', {
                method: method,
                path: path,
                params: params,
                body: body,
                response_code: response.code,
                www_authenticate: response['WWW-Authenticate']
            })

            error_msg = "NetSuite API error #{response.code}: #{response.body}"
            error_msg += " | WWW-Authenticate: #{response['WWW-Authenticate']}" if response['WWW-Authenticate']
            raise error_msg
        end
    end

    # Generates the authorization header for making requests

    class Headers
        def initialize(url:, method:, params:, credentials:)
            @url = url
            @method = method
            @params = params
            @account_id = credentials[:account_id]
            @consumer_key = credentials[:consumer_key]
            @consumer_secret = credentials[:consumer_secret]
            @token_id = credentials[:token_id]
            @token_secret = credentials[:token_secret]
            @signature_key = "#{escape(@consumer_secret)}&#{escape(@token_secret)}"
        end

        # Generates the request signature and authorization header

        def generate
            generate_nonce
            generate_timestamp
            generate_signature_data
            @digest = OpenSSL::HMAC.digest(OpenSSL::Digest.new('sha256'), @signature_key, @signature_data)
            @signature = Base64.strict_encode64(@digest)
            authorization_parts = {
                realm: @account_id,
                oauth_consumer_key: escape(@consumer_key),
                oauth_token: escape(@token_id),
                oauth_signature_method: 'HMAC-SHA256',
                oauth_timestamp: @timestamp,
                oauth_nonce: escape(@nonce),
                oauth_version: '1.0',
                oauth_signature: escape(@signature)
            }

            @authorization = "OAuth #{authorization_parts.map { |k, v| "#{k}=\"#{v}\"" }.join(',')}"
            @headers = { 'Authorization' => @authorization }
        end

        # It may seem like this does a lot of strange stuff, but the sorting of the keys is
        # critical to forming a valid signature.
        def generate_signature_data
            oauth_params = {
                oauth_consumer_key: @consumer_key,
                oauth_nonce: @nonce,
                oauth_signature_method: 'HMAC-SHA256',
                oauth_timestamp: @timestamp,
                oauth_token: @token_id,
                oauth_version: '1.0'
            }

            merged_params = @params.merge(oauth_params)
            merged_params.transform_keys!(&:to_sym)
            merged_params = merged_params.sort.to_h
            params_string = URI.encode_www_form(merged_params).gsub('+', '%20')

            @signature_data = [
                @method,
                escape(@url),
                escape(params_string)
            ].join('&')
        end

        def generate_nonce
            @nonce = Array.new(20) { [*'0'..'9', *'A'..'Z', *'a'..'z'].sample }.join
        end

        def generate_timestamp
            @timestamp = Time.now.to_i
        end

        def escape(str)
            ERB::Util.url_encode(str)
        end
    end

    # Base class for NetSuite Records
    class Record
        attr_reader :body

        @@allow_expanded_subresources = %w[itemGroup customer estimate salesOrder purchaseOrder]

        def initialize(props); end

        def self.count(query: nil)
            client = Client.new
            params = { offset: 0, limit: 1 }
            params[:q] = query if query
            response = client.list_records(object: @object, params:)
            response['totalResults'].to_i
        end

        def self.find_each(query: nil, offset: 0, limit: 1000)
            client = Client.new
            has_more = true
            while has_more
                params = { offset:, limit: }
                params[:q] = query if query
                response = client.list_records(object: @object, params:)
                response['items'].each do |item|
                    internal_id = item['id']
                    yield(internal_id)
                end
                has_more = response['hasMore']
                offset = response['offset'].to_i + response['count'].to_i
            end
        end

        def self.find_each_in_batches(query: nil, offset: 0, limit: 1000)
            client = Client.new
            has_more = true
            while has_more
                params = { offset:, limit: }
                params[:q] = query if query
                response = client.list_records(object: @object, params:)
                ids = response['items'].map { |item| item['id'] }
                yield(ids)
                has_more = response['hasMore']
                offset = response['offset'].to_i + response['count'].to_i
            end
        end

        def self.find(id, raise_on_not_found: true)
            raise ArgumentError, "#{name}.find requires an id, got: #{id.inspect}" if id.nil? || id.to_s.empty?

            client = Client.new
            params = {}
            params[:expandSubResources] = true if @@allow_expanded_subresources.include? @object
            # Skip 401 retries when we're just checking if record exists/has correct type
            client.get_record(object: @object, id:, params:, retry_on_401: raise_on_not_found)
        rescue RuntimeError => e
            # Handle 404 errors gracefully if requested
            if !raise_on_not_found && e.message.include?('404') && e.message.include?('NONEXISTENT_ID')
                Rails.logger.warn "[NetSuite] Record not found: #{@object} #{id} (404 NONEXISTENT_ID)"
                return nil
            end
            # Handle 401 errors when checking record type - item exists but wrong type
            if !raise_on_not_found && e.message.include?('401')
                Rails.logger.warn "[NetSuite] Item #{id} is not a #{@object} (401 - wrong record type)"
                return nil
            end
            raise
        end

        def self.find_external(external_id)
            raise ArgumentError, "#{name}.find_external requires an external_id" if external_id.nil? || external_id.to_s.empty?

            client = Client.new
            params = {}
            params[:expandSubResources] = true if @@allow_expanded_subresources.include? @object
            client.get_record(object: @object, external_id:, params:)
        end

        def self.delete(id)
            client = Client.new
            client.delete_record(object: @object, id:)
        end

        def self.delete_external(id)
            client = Client.new
            client.delete_record(object: @object, external_id: id)
        end

        def self.update(id, body, replace_item: false)
            client = Client.new
            params = replace_item ? { replace: 'item' } : {}
            client.update_record(object: @object, id:, body:, params:)
        end

        def self.list_subrecords(id:, subrecord:)
            client = Client.new
            client.list_records(object: "#{@object}/#{id}/#{subrecord}")
        end

        def self.assign_external_id(id, external_id)
            update(id, { 'externalId' => external_id })
        end

        def self.id_hash
            hash = {}
            ids = []
            find_each do |id|
                ids << id
            end

            ids.each do |id|
                record = find(id)
                hash[record['name']] = record['id']
            end
            hash
        end

        def create
            puts @body
            client = Client.new
            client.create_record(object: @object, body: @body)
        end

        def update(id)
            puts @body
            client = Client.new
            client.update_record(object: @object, id:, body: @body, params: { replace: 'item' })
        end
    end

    # Base Class for Transaction Records which allow for the addition of items
    # and item groups to the body

    class TransactionRecord < Record
        def add_item(id:, quantity:, amount: 0, rate: nil)
            new_item = {
                key: id,
                item: {
                    id:
                },
                quantity: quantity.to_i,
                amount: amount.to_i
            }

            new_item[:rate] = rate if rate
            new_item[:item][:rate] = rate if rate
            @body[:item][:items].push(new_item)
        end

        def add_item_group(id:, quantity:, amount: 0)
            item_group = ItemGroup.find(id).dig('member', 'items')
            item_group&.map do |item|
                item_id = item['item']['id']

                add_item(id: item_id, quantity:, amount:)
            end
        end
    end

    # Customer Class

    class Customer < Record
        @object = 'customer'

        def self.find_by(email: nil, phone: nil)
            # Instantiate Netsuite Client
            client = Netsuite::Client.new
            customer_id = nil

            # Infer Customer ID from API's. Check by email and phone in primary and secondary email fields.
            # TODO: Add secondary email and phone fields to customer record in ns and query as well!
            if email
                email_query = client.query(object: 'customer', query: "email CONTAIN \"#{email}\"")
                has_email_match = email_query['totalResults'].to_i.positive?
                customer_id = email_query.dig('items', -1, 'id') if has_email_match
            end

            if phone
                phone_query = client.query(object: 'customer', query: "phone CONTAIN \"#{phone}\"")
                has_phone_match = phone_query['totalResults'].to_i.positive?
                customer_id = phone_query.dig('items', -1, 'id') if has_phone_match
            end
            customer_id
        end

        def initialize(props)
            @object = 'customer'
            @first_name = props[:first_name]
            @last_name = props[:last_name]
            @email = props[:email]
            @phone = props[:phone]
            @address = props[:address]
            @city = props[:city]
            @state = props[:state]
            @zip = props[:zip]
            generate_body
            super
        end

        def generate_body
            @body = {
                firstName: @first_name,
                lastName: @last_name,
                isPerson: true,
                email: @email,
                phone: @phone,
                addressbook: {
                    items: [
                        {
                            label: 'Main Address',
                            addressbookAddress: {
                                addressee: "#{@first_name} #{@last_name}",
                                addrPhone: @phone,
                                addr1: @address,
                                city: @city,
                                state: @state,
                                zip: @zip
                            },
                            defaultBilling: true,
                            defaultShipping: true,
                            isResidential: true
                        }
                    ]
                }
            }
        end
    end

    # Project Class

    class Project < Record
        @object = 'job'

        def initialize(props)
            @object = 'job'
            @customer_id = props[:customer_id].to_i
            @project_id = props[:project_id].to_i
            @entity_id = props[:entity_id]
            generate_body
            super
        end

        def generate_body
            @body = {
                externalId: @project_id.to_s,
                accountNumber: @customer_id,
                companyName: @entity_id,
                entityId: @project_id.to_i.to_s,
                autoName: false,
                parent: {
                    id: @customer_id
                },
                customer: {
                    id: @customer_id
                }

            }
            @body[:projectExpenseType] = { id: -2 } if Rails.env.development?
            @body
        end
    end

    class Vendor < Record
        @object = 'vendor'

        def initialize(props)
            @object = 'vendor'
            @body = props
            super
        end
    end

    # Estimate Class
    class Estimate < TransactionRecord
        @object = 'estimate'

        def initialize(props)
            @object = 'estimate'
            @customer_id = props[:customer_id]
            @project_id = props[:project_id]
            @internal_project_id = props[:internal_project_id]
            @location_id = props[:location_id]
            @terms = props[:terms]
            @payment_description = props[:payment_description]
            generate_body
            super
        end

        def generate_body
            @body = {
                externalId: "estimate_#{@project_id}",
                entity: {
                    id: @customer_id
                },
                job: {
                    id: @internal_project_id
                },
                department: 6,
                location: @location_id,
                class: 1,
                terms: @terms,
                custbodypayment_description: @payment_description,
                item: {
                    items: []
                }
            }
        end
    end

    # Sales Order Class
    class SalesOrder < TransactionRecord
        @object = 'salesOrder'

        def initialize(props)
            @object = 'salesOrder'
            @customer_id = props[:customer_id]
            @project_id = props[:project_id]
            @internal_project_id = props[:internal_project_id]
            @location_id = props[:location_id]
            @terms = props[:terms]
            @payment_description = props[:payment_description]
            @status = props[:status]

            generate_body
            super
        end

        def generate_body
            @body = {
                externalId: "sales_order_#{@project_id}",
                entity: {
                    id: @customer_id
                },
                job: {
                    id: @internal_project_id
                },
                department: 6,
                location: @location_id,
                class: 1,
                terms: @terms,
                custbodypayment_description: @payment_description,
                item: {
                    items: []
                }
            }
            @body[:status] = @status if @status
            @body
        end

        def self.close(sales_order)
            body_item = sales_order['item']

            # Adding Status to each item of "Closed"
            body_item['items'].each do |item|
                item['isClosed'] = true
            end

            closing_memo = "Closed by the Proposal Tool API due to cancellation on #{Date.today.strftime('%m/%d/%Y')}"
            body = {
                item: body_item,
                status: 'H',
                custbody_cancellation_date: Date.today.to_s,
                memo: closing_memo
            }

            # Updating the Sales Order
            update(sales_order['id'], body)
        end

        # Close specific line items on a Sales Order without closing the entire SO
        # @param sales_order_id [Integer] The internal ID of the Sales Order
        # @param line_numbers [Array<Integer>] The line numbers to close
        # @return [String] The response body from the update
        def self.close_specific_lines(sales_order_id, line_numbers)
            sales_order = find(sales_order_id)
            body_item = sales_order['item']

            # Close only the specified lines
            body_item['items'].each do |item|
                item['isClosed'] = true if line_numbers.include?(item['line'])
            end

            # Note: Do NOT set status: 'H' here as that closes the entire SO
            body = { item: body_item }
            update(sales_order_id, body)
        end
    end

    class RevenueArrangement < TransactionRecord
        @object = 'revenueArrangement'

        def initialize(props)
            @object = 'revenueArrangement'

            generate_body
            super
        end

        def generate_body
            @body = {
                item: {
                    items: []
                }
            }
            @body
        end
    end

    class ChangeOrder < Record
        @object = 'customrecord_change_order'

        def initialize(props)
            @object = 'customrecord_change_order'
            @date = props[:date]
            @materials_change = props[:materials_change]
            @payment_method_change = props[:payment_method_change]
            @price_change = props[:price_change]
            @transaction = props[:sales_order_id]
            @type = props[:type]
            @description = props[:description]
            generate_body
            super
        end

        def generate_body
            @body = {
                custrecord_co_date: @date,
                custrecord_co_materials_change: @materials_change,
                custrecord_co_payment_method_change: @payment_method_change,
                custrecord_co_price_change: @price_change,
                custrecord_co_transaction: @transaction,
                custrecord_co_type: @type,
                custrecord_co_description: @description
            }
        end

        def self.find_by_sales_order(id)
            client = Client.new
            client.query(object: @object, query: "custrecord_co_transaction ANY_OF [#{id}]")
        end
    end

    # Service Titan Sync
    class ServiceTitanCustomerSyncRecord < Record
        @object = 'customrecord_st_tenant_cust'

        def initialize(props)
            @object = 'customrecord_st_tenant_cust'
            @service_titan_customer_id = props[:service_titan_customer_id]
            @service_titan_customer_name = props[:service_titan_customer_name]
            @netsuite_customer_id = props[:netsuite_customer_id]
            @service_titan_tenant_id = Rails.application.credentials.service_titan[:tenant_id]
            @external_id = "#{@service_titan_tenant_id}_#{@service_titan_customer_id}_1"

            generate_body
            super
        end

        def generate_body
            @body = {
                custrecord_st_tn_cust_tenant: { id: 1 },
                custrecord_st_tn_cust_id: @service_titan_customer_id,
                custrecord_st_tn_cust_name: @service_titan_customer_name,
                custrecord_st_tn_cust_ns_rec: { id: @netsuite_customer_id },
                custrecord_st_tn_cust_ns_id: @netsuite_customer_id.to_i,
                externalId: @external_id
            }
        end

        def self.find_by_netsuite_service_titan_customer_id(service_titan_customer_id)
            client = Client.new
            query = "custrecord_st_tn_cust_id EQUAL #{service_titan_customer_id}"
            client.query(object: @object, query:)
        end
    end

    # Invoice Class

    class Invoice < TransactionRecord
        @object = 'invoice'

        def initialize(props)
            @object = 'invoice'
            @customer_id = props[:customer_id]
            @location_id = props[:location_id]
            @sales_order_id = props[:sales_order_id]
            generate_body
            super
        end

        def generate_body
            @body = {
                entity: {
                    id: @customer_id
                },
                salesOrder: {
                    id: @sales_order_id
                },
                location: @location_id,
                class: 1,
                item: {
                    items: []
                }
            }
        end

        def set_payment_details(amount:, payment_option:, payment_description:, payment_milestone:)
            @body[:payment] = amount
            @body[:paymentOption] = payment_option
            @body[:custbodypayment_description] = payment_description
            @body[:custbodyexecution_milestone] = payment_milestone
            @body
        end
    end

    # Customer Deposit Class
    class CustomerDeposit < Record
        @object = 'customerDeposit'

        def initialize(props)
            @object = 'customerDeposit'
            @customer_id = props[:customer_id]
            @location_id = props[:location_id]
            @sales_order_id = props[:sales_order_id]
            # @internal_project_id = props[:internal_project_id]
            generate_body
            super
        end

        def generate_body
            @body = {
                customer: {
                    id: @customer_id
                },
                salesOrder: {
                    id: @sales_order_id
                },
                location: @location_id
            }
        end

        def set_payment_details(amount:, payment_option:, payment_description:, payment_milestone:)
            @body[:payment] = amount
            @body[:paymentOption] = payment_option
            @body[:custbodypayment_description] = payment_description
            @body[:custbodyexecution_milestone] = payment_milestone
            @body
        end
    end

    # Purchase Order Class
    class PurchaseOrder < TransactionRecord
        @object = 'purchaseOrder'

        # RESTlet script and deploy IDs for PDF generation
        # Update these after deploying the restlet_po_pdf.js script in NetSuite
        PDF_RESTLET_SCRIPT_ID = 4135
        PDF_RESTLET_DEPLOY_ID = 1

        def initialize(props)
            @object = 'purchaseOrder'
            @vendor = props[:vendor]
            @vendor_name = props[:vendor_name]
            @customer_id = props[:customer_id]
            @project_id = props[:project_id]
            @internal_project_id = props[:internal_project_id]
            @location_id = props[:location_id]
            @tran_id = props[:tran_id]
            @customer_ship_to = props[:customer_ship_to]
            generate_body
            super
        end

        def generate_body
            @body = {
                externalId: "purchase_order_#{@vendor}_#{@project_id.to_i}",
                tranId: @tran_id || "#{@vendor_name}: #{@project_id.to_i}",
                exchangeRate: 1,
                location: @location_id,
                entity: { id: @vendor },
                job: { id: @internal_project_id },
                class: 1,
                department: nil,
                custbody1: false,
                custbody_po_customer: @customer_id,
                custbody_po_customer_project: { id: @internal_project_id },
                custbody_po_cust_ship_to: @customer_ship_to,
                item: {
                    items: []
                }
            }
        end

        def add_item(id:, quantity:, amount: nil, rate: nil)
            new_item = {
                customer: { id: @internal_project_id },
                item: { id: id },
                quantity: quantity.to_i,
                class: { id: 1 },
                location: @location_id,
                isBillable: true
            }
            new_item[:amount] = amount.to_i if amount
            new_item[:rate] = rate if rate
            @body[:item][:items].push(new_item)
        end

        # Fetch PDF for a Purchase Order via RESTlet
        # Returns hash with :success, :content (base64), :fileName, :error
        def self.fetch_pdf(po_id)
            unless PDF_RESTLET_SCRIPT_ID && PDF_RESTLET_DEPLOY_ID
                raise 'PDF RESTlet not configured. Set PDF_RESTLET_SCRIPT_ID and PDF_RESTLET_DEPLOY_ID'
            end

            client = Client.new
            client.call_restlet(
                script_id: PDF_RESTLET_SCRIPT_ID,
                deploy_id: PDF_RESTLET_DEPLOY_ID,
                params: { poId: po_id }
            )
        end

        # Fetch PDF and decode to binary
        # Returns the raw PDF binary data
        def self.fetch_pdf_binary(po_id)
            result = fetch_pdf(po_id)
            raise result['error'] unless result['success']

            Base64.decode64(result['content'])
        end

        # Fetch PDF and save to a file
        def self.save_pdf_to_file(po_id, file_path)
            pdf_binary = fetch_pdf_binary(po_id)
            File.binwrite(file_path, pdf_binary)
            file_path
        end

        # Close a Purchase Order by closing all its line items
        # @param po_id [Integer] The internal ID of the Purchase Order
        # @param line_numbers [Array<Integer>, nil] Optional specific line numbers to close; closes all if nil
        # @return [String] The response body from the update
        def self.close(po_id, line_numbers = nil)
            purchase_order = find(po_id)
            body_item = purchase_order['item']

            if line_numbers.nil?
                # Close all items
                body_item['items'].each do |item|
                    item['isClosed'] = true
                end
            else
                # Close only specific line numbers
                body_item['items'].each do |item|
                    item['isClosed'] = true if line_numbers.include?(item['line'])
                end
            end

            body = { item: body_item }
            update(po_id, body)
        end
    end

    # Discount Item Class
    class DiscountItem < Record
        @object = 'discountItem'

        def initialize
            @object = 'discountItem'
            super
        end
    end

    # Inventory Item Class
    class InventoryItem < Record
        @object = 'inventoryItem'

        def initialize
            @object = 'inventoryItem'
            super
        end
    end

    # Item Group Class
    class ItemGroup < Record
        @object = 'itemGroup'

        def initialize
            @object = 'itemGroup'
            super
        end
    end

    # Service Sale Item Class
    class ServiceSaleItem < Record
        @object = 'serviceSaleItem'

        def initalize
            @object = 'serviceSaleItem'
            super
        end
    end

    # Service Resale Item Class
    class ServiceResaleItem < Record
        @object = 'serviceResaleItem'

        def initalize
            @object = 'serviceResaleItem'
            super
        end
    end

    # Other Charge Sale Item Class

    class OtherChargeSaleItem < Record
        @object = 'otherChargeSaleItem'

        def initialize
            @object = 'otherChargeSaleItem'
            super
        end
    end

    # Lender
    class Lender < Record
        @object = 'customlistlender'
        def initialize
            @object = 'customlistlender'
            super
        end
    end

    class ServiceProjectType < Record
        @object = 'customlist_service_project_types'
        def initialize
            @object = 'customlist_service_project_types'
            super
        end
    end

    class RmaType < Record
        @object = 'customlist_rma_type'
        def initialize
            @object = 'customlist_rma_type'
            super
        end
    end
end

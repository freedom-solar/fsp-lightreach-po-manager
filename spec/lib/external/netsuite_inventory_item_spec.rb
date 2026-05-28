require "rails_helper"

RSpec.describe Netsuite::InventoryItem do
  describe ".fetch_details_by_ids" do
    let(:client) { instance_double(Netsuite::Client) }

    before do
      allow(Netsuite::Client).to receive(:new).and_return(client)
    end

    def stub_suiteql_response(rows)
      allow(client).to receive(:suiteql).and_return({ "items" => rows })
    end

    it "returns a hash keyed by integer id" do
      stub_suiteql_response([
        { "id" => "857", "itemid" => "MSX10-435HN0B", "itemtype" => "InvtPart", "custitem1" => "2" }
      ])

      result = described_class.fetch_details_by_ids([ 857 ])

      expect(result).to be_a(Hash)
      expect(result.keys).to eq([ 857 ])
      expect(result[857]["itemid"]).to eq("MSX10-435HN0B")
      expect(result[857]["itemtype"]).to eq("InvtPart")
      expect(result[857]["custitem1"]).to eq("2")
    end

    it "short-circuits without an API request on empty input" do
      expect(Netsuite::Client).not_to receive(:new)
      expect(described_class.fetch_details_by_ids([])).to eq({})
    end

    it "short-circuits when all ids are nil/non-numeric" do
      expect(Netsuite::Client).not_to receive(:new)
      expect(described_class.fetch_details_by_ids([ nil, "", "abc" ])).to eq({})
    end

    it "coerces string ids to integers" do
      stub_suiteql_response([
        { "id" => "857", "itemid" => "MSX10-435HN0B", "itemtype" => "InvtPart", "custitem1" => "2" }
      ])

      result = described_class.fetch_details_by_ids([ "857" ])
      expect(result[857]).to be_present
    end

    it "deduplicates ids and drops invalid ones before querying" do
      expect(client).to receive(:suiteql) do |query:|
        # Should query 857 and 776 once each, ignore the nil/"abc"
        expect(query).to match(/IN \((857|776),\s*(857|776)\)/)
        { "items" => [] }
      end

      described_class.fetch_details_by_ids([ 857, 857, "776", nil, "abc", 0 ])
    end

    it "returns hash without entry for ids not found in NetSuite" do
      stub_suiteql_response([
        { "id" => "857", "itemid" => "MSX10-435HN0B", "itemtype" => "InvtPart", "custitem1" => "2" }
      ])

      result = described_class.fetch_details_by_ids([ 857, 999_999_999 ])
      expect(result).to have_key(857)
      expect(result).not_to have_key(999_999_999)
    end

    it "returns {} when SuiteQL returns no items array" do
      allow(client).to receive(:suiteql).and_return({})
      expect(described_class.fetch_details_by_ids([ 857 ])).to eq({})
    end

    it "propagates errors instead of silently swallowing them" do
      allow(client).to receive(:suiteql).and_raise(RuntimeError, "401 Unauthorized")
      expect {
        described_class.fetch_details_by_ids([ 857 ])
      }.to raise_error(RuntimeError, /401/)
    end

    it "includes the columns the PO generation logic depends on" do
      query_sent = nil
      allow(client).to receive(:suiteql) do |query:|
        query_sent = query
        { "items" => [] }
      end

      described_class.fetch_details_by_ids([ 857 ])

      # The fix depends on these specific columns being requested
      %w[id itemid itemtype custitem1].each do |column|
        expect(query_sent).to include(column), "expected SuiteQL to select #{column}, got: #{query_sent}"
      end
    end
  end
end

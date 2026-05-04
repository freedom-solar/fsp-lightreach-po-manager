require "rails_helper"

RSpec.describe DataFormatter do
  let(:test_class) do
    Class.new do
      include DataFormatter
    end
  end
  let(:formatter) { test_class.new }

  describe "#convert_number_to_currency_string" do
    it "converts number to currency string" do
      expect(formatter.convert_number_to_currency_string(1234.56)).to eq("$1,235")
    end

    it "respects precision parameter" do
      expect(formatter.convert_number_to_currency_string(1234.56, precision: 2)).to eq("$1,234.56")
    end

    it "returns empty string for nil" do
      expect(formatter.convert_number_to_currency_string(nil)).to eq("")
    end

    it "returns empty string for blank value" do
      expect(formatter.convert_number_to_currency_string("")).to eq("")
    end
  end

  describe "#convert_number_to_percent_string" do
    it "converts number to percentage string" do
      expect(formatter.convert_number_to_percent_string(0.85)).to eq("85%")
    end

    it "respects precision parameter" do
      expect(formatter.convert_number_to_percent_string(0.8567, precision: 2)).to eq("85.67%")
    end

    it "returns empty string for nil" do
      expect(formatter.convert_number_to_percent_string(nil)).to eq("")
    end

    it "returns empty string for blank value" do
      expect(formatter.convert_number_to_percent_string("")).to eq("")
    end
  end

  describe "#convert_timezone" do
    it "maps America/New_York to EST" do
      expect(formatter.convert_timezone("America/New_York")).to eq("EST")
    end

    it "maps America/Chicago to America/Chicago" do
      expect(formatter.convert_timezone("America/Chicago")).to eq("America/Chicago")
    end

    it "maps US/Mountain to MST" do
      expect(formatter.convert_timezone("US/Mountain")).to eq("MST")
    end

    it "maps US/Eastern to EST" do
      expect(formatter.convert_timezone("US/Eastern")).to eq("EST")
    end

    it "returns nil for unmapped timezone" do
      expect(formatter.convert_timezone("Europe/London")).to be_nil
    end
  end

  describe "#convert_unix_to_date_str?" do
    it "converts unix timestamp to date string" do
      unix_str = "1609545600000" # 2021-01-02 00:00:00 UTC (will be 01/01/2021 in CST/EST)
      result = formatter.convert_unix_to_date_str?(unix_str)
      expect(result).to match(/\d{2}\/\d{2}\/\d{4}/)
    end

    it "returns empty string for nil" do
      expect(formatter.convert_unix_to_date_str?(nil)).to eq("")
    end

    it "returns empty string for blank value" do
      expect(formatter.convert_unix_to_date_str?("")).to eq("")
    end
  end

  describe "#convert_unix_to_date_obj?" do
    it "converts unix timestamp to date object" do
      unix_str = "1609545600000" # 2021-01-02 00:00:00 UTC
      result = formatter.convert_unix_to_date_obj?(unix_str)
      expect(result).to be_a(Date)
      expect(result.year).to eq(2021)
      expect(result.month).to be_between(1, 2)
    end

    it "returns nil for blank value" do
      expect(formatter.convert_unix_to_date_obj?("")).to be_nil
    end

    it "returns nil for nil" do
      expect(formatter.convert_unix_to_date_obj?(nil)).to be_nil
    end
  end

  describe "#convert_to_date_time_str?" do
    it "converts date string to time in timezone" do
      result = formatter.convert_to_date_time_str?("2021-01-01 12:00:00", "America/Chicago")
      expect(result).to be_a(Time)
    end

    it "returns error message for blank timezone" do
      result = formatter.convert_to_date_time_str?("2021-01-01 12:00:00", "")
      expect(result).to include("timezone:")
      expect(result).to include("was blank")
    end

    it "returns error message for blank date" do
      result = formatter.convert_to_date_time_str?("", "America/Chicago")
      expect(result).to include("date_obj:")
      expect(result).to include("was blank")
    end
  end
end

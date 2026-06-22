require 'rails_helper'

RSpec.describe ProgramType do
  describe '.for' do
    it 'classifies Lightreach Lease projects as Direct Pay' do
      project = { 'fields' => { 'lender' => 'Lightreach Lease' } }
      expect(described_class.for(project)).to eq(described_class::DIRECT_PAY)
    end

    it 'classifies any other lender as a CED Kitted Job' do
      project = { 'fields' => { 'lender' => 'Cash' } }
      expect(described_class.for(project)).to eq(described_class::CED_KITTED)
    end

    it 'classifies a missing lender as a CED Kitted Job' do
      expect(described_class.for({ 'fields' => {} })).to eq(described_class::CED_KITTED)
    end
  end

  describe '.for_key' do
    it 'returns the matching program for a known key' do
      expect(described_class.for_key(:ced_kitted)).to eq(described_class::CED_KITTED)
      expect(described_class.for_key('direct_pay')).to eq(described_class::DIRECT_PAY)
    end

    it 'falls back to Direct Pay for blank/unknown keys (legacy po_results)' do
      expect(described_class.for_key(nil)).to eq(described_class::DIRECT_PAY)
      expect(described_class.for_key('mystery')).to eq(described_class::DIRECT_PAY)
    end
  end

  describe 'program definitions' do
    it 'uses distinct vendors and zero-pricing only for Direct Pay' do
      expect(described_class::DIRECT_PAY[:vendor_id]).to eq(2_660_586)
      expect(described_class::DIRECT_PAY[:zero_priced]).to be true
      expect(described_class::CED_KITTED[:vendor_id]).to eq(1054)
      expect(described_class::CED_KITTED[:zero_priced]).to be false
    end

    it 'never labels a CED Kitted Job as Lightreach' do
      expect(described_class::CED_KITTED[:label]).not_to include('Lightreach')
    end
  end
end

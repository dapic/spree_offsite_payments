require 'spec_helper'
require 'pp'

describe Spree::OffsitePayments::Wxpay do
  before(:all) {
    Rails.logger.level = Logger::DEBUG
    create(:wxpay_payment_method)
    create(:wxpay_payment)
  }

  before { allow(SecureRandom).to receive(:hex).and_return('fake_nonce_str') }

  let(:payment_method) { Spree::OffsitePayments::Wxpay.payment_method }
  let(:wxpay_payment) { Spree::Payment.last }
  let(:wxpay) { Spree::OffsitePayments::Wxpay }
  let(:request) { double( host: 'http://test.sample.com/', remote_ip: '10.10.10.1' ) }

  it 'needs its model_class to work' do
    expect( payment_method ).not_to be_nil
    expect( payment_method.preferred_appid ).to eq 'wxpay_app_id'
    expect( payment_method.preferred_appsecret ).to eq 'wxpay_app_secret'
    expect( payment_method.preferred_mch_id ).to eq 'wxpay_mch_id'
  end

  it 'needs to be set up' do

  end

  it '#assemble_payload' do
    payload = wxpay.assemble_payload(:unifiedorder, wxpay_payment, request: request, wx_trade_type: 'JSAPI', client_openid: 'sample_client_open_id')
    expect(payload).to be_a Hash
    expect(payload[:openid]).to eq 'sample_client_open_id'
    payload = wxpay.assemble_payload(:unifiedorder, wxpay_payment, {request: request, wx_trade_type: 'JSAPI', client_openid: 'sample_client_open_id'})
    expect(payload[:openid]).to eq 'sample_client_open_id'
  end

  it '#send_request' do
    payload = wxpay.assemble_payload(:unifiedorder, wxpay_payment, request: request, wx_trade_type: 'JSAPI', client_openid: 'sample_client_open_id')
    expect(wxpay).to receive(:send_api_request).with(:unifiedorder, payload)
    wxpay.send_request(:unifiedorder, wxpay_payment, request: request, wx_trade_type: 'JSAPI', client_openid: 'sample_client_open_id')
    expect(payload).to be_a Hash
    expect(payload[:openid]).to eq 'sample_client_open_id'
  end

  describe Spree::OffsitePayments::Wxpay::Manager do

    let( :manager ) { Spree::OffsitePayments::Wxpay::Manager.new }
    it 'creates a new instance with credentials set in module' do
      expect( Spree::OffsitePayments::Wxpay::Manager.new ).not_to be_nil
    end

    it 'has a valid auth_client' do
      expect( manager.auth_client ).not_to be_nil
      expect( manager.auth_client ).to be_a WeixinAuthorize::Client
      client = manager.auth_client
      expect( client.app_id ).to eq 'wxpay_app_id'
      expect( client.app_secret ).to eq 'wxpay_app_secret'
      #pp manager.inspect
      #pp client.inspect
    end

    it 'could produce authorize_url' do
      return_url = 'http://test.shiguangcaibei.com/'
      url = manager.get_authorize_url(return_url)
      pp url
      expect( url ).to match(/https:\/\/.*/)
      expect( url ).to match(/.*#{CGI::escape(return_url)}.*scope=snsapi_base&state=payment#wechat_redirect/)

    end

    it '#get_client_open_id' do
      expect( RestClient ).to receive(:get).and_return( get_access_token_result )
      result = manager.get_client_openid('test_oauth_code')
      expect( result ).to be_a WeixinAuthorize::ResultHandler
      expect( result.result['access_token'] ).to eq "ACCESS_TOKEN"
      expect( result.result['openid'] ).to eq "OPENID"
    end

    it '#get_prepay_id for JSAPI' do
      payment = Spree::Payment.last
      allow_any_instance_of( OffsitePayments::Integrations::Wxpay::UnifiedOrderHelper ).to receive(:ssl_post).and_return( unified_order_response_jsapi_success )
      result = manager.get_prepay_id( payment, request, client_openid: 'CLIENT_OPENID')
      expect(result).to be_a String
      expect(result).to eq 'wx20141125175855641523fd940589543551'
    end

    it '#get_payment_url for NATIVE trade_type' do
      payment = Spree::Payment.last
      request = double( host: 'http://test.sample.com/', remote_ip: '10.10.10.1' )
      allow_any_instance_of( OffsitePayments::Integrations::Wxpay::UnifiedOrderHelper ).to receive(:ssl_post).and_return( unified_order_response_native_success )
      result = manager.get_payment_url( payment, request )
      expect(result).to be_a String
      expect(result).to eq 'weixin://wxpay/bizpayurl?sr=tVLUP6i'
    end

    it '#get_wcpay_request_payload' do
      payload = manager.get_wcpay_request_payload('sample_prepay_id')
      expect(payload['appId']).to eq 'wxpay_app_id'
      expect(payload['timeStamp'].to_i).to be_within(3).of(Time.now.to_i)
      expect(payload['timeStamp'].to_i).to be_within(3).of(Time.now.to_i)
      expect(payload['package']).to eq "prepay_id=sample_prepay_id"
      expect(payload['signType']).to eq "MD5"
      expect(payload['nonceStr']).to eq 'fake_nonce_str'
      expect(payload['paySign'].length).to eq 32
    end
  end

  def get_access_token_result
    <<-EOF
    {
    "access_token":"ACCESS_TOKEN", "expires_in":7200, "refresh_token":"REFRESH_TOKEN", "openid":"OPENID", "scope":"SCOPE"
    }
    EOF
  end

  def unified_order_response_jsapi_success
    <<-EOF
    <xml><return_code><![CDATA[SUCCESS]]></return_code>
    <return_msg><![CDATA[OK]]></return_msg>
    <appid><![CDATA[wxpay_app_id]]></appid>
    <mch_id><![CDATA[wxpay_mch_id]]></mch_id>
    <nonce_str><![CDATA[gHnTo0kDg56P0Y6T]]></nonce_str>
    <sign><![CDATA[A6E1B1BA3BEC382259212D4262583717]]></sign>
    <result_code><![CDATA[SUCCESS]]></result_code>
    <prepay_id><![CDATA[wx20141125175855641523fd940589543551]]></prepay_id>
    <trade_type><![CDATA[JSAPI]]></trade_type>
    </xml>
    EOF
  end

  def unified_order_response_native_success
    <<-EOF
    <xml><return_code><![CDATA[SUCCESS]]></return_code>
    <return_msg><![CDATA[OK]]></return_msg>
    <appid><![CDATA[wxpay_app_id]]></appid>
    <mch_id><![CDATA[wxpay_mch_id]]></mch_id>
    <nonce_str><![CDATA[gHnTo0kDg56P0Y6T]]></nonce_str>
    <sign><![CDATA[3FF1B3C6528920B08C23EADE9A7B861B]]></sign>
    <result_code><![CDATA[SUCCESS]]></result_code>
    <prepay_id><![CDATA[wx20141125175855641523fd940589543551]]></prepay_id>
    <trade_type><![CDATA[NATIVE]]></trade_type>
    <code_url><![CDATA[weixin://wxpay/bizpayurl?sr=tVLUP6i]]></code_url>
    </xml>
    EOF
  end
end

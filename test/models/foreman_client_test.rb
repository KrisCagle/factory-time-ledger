require "test_helper"

class ForemanClientTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body, :message) do
    def is_a?(klass) = klass == Net::HTTPSuccess ? code.to_i.between?(200, 299) : super
  end

  class Recorder
    attr_reader :requests

    def initialize(response) = (@response = response; @requests = [])
    def request(req) = (@requests << req; @response)
  end

  def with_response(code, body)
    recorder = Recorder.new(FakeResponse.new(code.to_s, body.to_json, "msg"))
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*_a, **_k, &blk| blk.call(recorder) }
    yield recorder
  ensure
    Net::HTTP.define_singleton_method(:start, original)
  end

  test "the challenge matches Foreman's: base64url SHA-256 with no padding" do
    challenge = ForemanApi::Client.challenge_for("a-verifier")
    assert_equal Base64.urlsafe_encode64(Digest::SHA256.digest("a-verifier"), padding: false), challenge
    assert_equal 43, challenge.length
  end

  test "the authorize URL names the tool, the challenge, a bare port, and state" do
    url = URI(ForemanApi::Client.authorize_url(challenge: "abc", state: "s1", port: 3001))
    assert_equal "/cli-auth/authorize", url.path
    query = URI.decode_www_form(url.query).to_h
    assert_equal({ "tool" => "factory-time-ledger", "name" => "Factory Time Ledger", "challenge" => "abc", "port" => "3001", "state" => "s1" }, query)
  end

  test "reads an inferred run with a GET and the bearer token" do
    with_response(200, { "build" => nil, "run" => { "id" => "jira:ACME-1" } }) do |rec|
      body = ForemanApi::Client.new(token: "tok").inferred_run("ACME-1")
      assert_equal "jira:ACME-1", body["run"]["id"]
      req = rec.requests.first
      assert_kind_of Net::HTTP::Get, req
      assert_equal "Bearer tok", req["Authorization"]
      assert_equal "/api/administration/v1/inferred-runs/jira:ACME-1", req.path
    end
  end

  test "every read is a GET; only the sign-in exchange posts, without a token" do
    with_response(200, {}) do |rec|
      client = ForemanApi::Client.new(token: "tok")
      client.me
      client.story_timeline("ACME-1")
      assert rec.requests.all? { |r| r.is_a?(Net::HTTP::Get) }

      ForemanApi::Client.new(token: nil).exchange(code: "c", verifier: "v")
      exchange = rec.requests.last
      assert_kind_of Net::HTTP::Post, exchange
      assert_equal "/cli-auth/exchange", exchange.path
      assert_nil exchange["Authorization"]
      assert_equal({ "code" => "c", "verifier" => "v" }, JSON.parse(exchange.body))
    end
  end

  test "explains a missing roster entry or scope" do
    with_response(403, { "detail" => "this needs a granted scope" }) do
      error = assert_raises(ForemanApi::Client::Error) { ForemanApi::Client.new(token: "tok").story_timeline("ACME-1") }
      assert error.forbidden?
      assert_match "granted scope", error.message
    end
  end

  test "refuses to read without a sign-in" do
    assert_raises(ForemanApi::Client::Error) { ForemanApi::Client.new(token: nil).me }
  end
end

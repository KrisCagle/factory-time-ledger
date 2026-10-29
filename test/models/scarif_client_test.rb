require "test_helper"

# Checks the real Scarif::Client's HTTP handling with Net::HTTP swapped for a
# recorder, so no network is used.
class ScarifClientTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body, :headers, :message) do
    def is_a?(klass) = klass == Net::HTTPSuccess ? code.to_i.between?(200, 299) : super
    def each_header = headers.each
  end

  class Recorder
    attr_reader :requests

    def initialize(response) = (@response = response; @requests = [])
    def request(req) = (@requests << req; @response)
  end

  setup { ENV["SCARIF_API_TOKEN"] = "test-token" }
  teardown { ENV.delete("SCARIF_API_TOKEN"); ENV.delete("SCARIF_URL") }

  def with_response(code, body, headers = {})
    recorder = Recorder.new(FakeResponse.new(code.to_s, body.to_json, headers, "msg"))
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*_args, **_kw, &blk| blk.call(recorder) }
    yield recorder
  ensure
    Net::HTTP.define_singleton_method(:start, original)
  end

  test "lists work items with a GET, bearer token, and pagination headers" do
    with_response(200, [{ "id" => "a1" }], { "x-has-more" => "true", "x-next-cursor" => "abc" }) do |rec|
      page = Scarif::Client.new.work_items(cursor: "prev")
      assert_equal ["a1"], page.items.map { |i| i["id"] }
      assert page.has_more
      assert_equal "abc", page.next_cursor

      req = rec.requests.first
      assert_kind_of Net::HTTP::Get, req
      assert_equal "Bearer test-token", req["Authorization"]
      assert_equal "/api/v2/work_items?limit=100&cursor=prev", req.path
    end
  end

  test "every call is a read-only GET" do
    with_response(200, { "user" => {}, "node_runs" => [], "asks" => [] }) do |rec|
      client = Scarif::Client.new
      client.me
      client.work_item("a1")
      client.node_runs("a1")
      client.factory_asks(jira_key: "ACME-1")
      assert_equal 4, rec.requests.size
      assert rec.requests.all? { |r| r.is_a?(Net::HTTP::Get) }
      assert_equal "/api/v2/factory_asks?state=all&jira_key=ACME-1", rec.requests.last.path
    end
  end

  test "uses SCARIF_URL when set" do
    ENV["SCARIF_URL"] = "https://scarif.example.test/"
    assert_equal "https://scarif.example.test", Scarif::Client.base_url
  end

  test "explains a rejected token" do
    with_response(401, { "error" => "nope" }) do
      error = assert_raises(Scarif::Client::Error) { Scarif::Client.new.me }
      assert_equal 401, error.status
      assert_match "rejected the token", error.message
    end
  end

  test "explains a missing scope" do
    with_response(403, { "error" => "insufficient_scope" }) do
      error = assert_raises(Scarif::Client::Error) { Scarif::Client.new.work_items }
      assert_match "work_item:read", error.message
    end
  end

  test "refuses to call Scarif without a token" do
    ENV.delete("SCARIF_API_TOKEN")
    assert_raises(Scarif::Client::Error) { Scarif::Client.new.me }
  end
end

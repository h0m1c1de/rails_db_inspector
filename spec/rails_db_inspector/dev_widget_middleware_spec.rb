# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsDbInspector::DevWidgetMiddleware do
  let(:inner_app) { ->(env) { [ 200, { "Content-Type" => "text/html" }, [ "<html><body></body></html>" ] ] } }
  subject(:middleware) { described_class.new(inner_app) }

  let(:env) { { "PATH_INFO" => "/some/page", "REQUEST_METHOD" => "GET" } }

  before do
    # Reset memoized mount path
    middleware.instance_variable_set(:@mount_path, nil)
  end

  describe "#call" do
    context "when mount path is found" do
      before do
        # Stub the route finding
        route_app = double("route_app", app: RailsDbInspector::Engine)
        allow(route_app).to receive(:respond_to?).with(:app).and_return(true)
        path_spec = double("path_spec", to_s: "/db_inspector(.:format)")
        route = double("route", app: route_app, path: double(spec: path_spec))
        routes = double("routes", routes: [ route ])
        app = double("rails_app", routes: routes)
        allow(Rails).to receive(:application).and_return(app)
      end

      it "injects widget HTML before </body>" do
        status, headers, body = middleware.call(env)

        html = body.first
        expect(html).to include("rdi-widget")
        expect(html).to include("DB Inspector")
        expect(html).to include("/db_inspector")
        expect(html).to include("</body>")
      end

      it "updates Content-Length header" do
        status, headers, body = middleware.call(env)

        expect(headers["Content-Length"]).to eq body.first.bytesize.to_s
      end
    end

    context "when response is not HTML" do
      let(:inner_app) { ->(env) { [ 200, { "Content-Type" => "application/json" }, [ '{"ok":true}' ] ] } }

      it "passes through without modification" do
        status, headers, body = middleware.call(env)

        expect(body).to eq [ '{"ok":true}' ]
      end
    end

    context "when status is not 200" do
      let(:inner_app) { ->(env) { [ 404, { "Content-Type" => "text/html" }, [ "<html><body>Not Found</body></html>" ] ] } }

      it "passes through without modification" do
        status, _headers, body = middleware.call(env)

        expect(status).to eq 404
        expect(body.first).not_to include("rdi-widget")
      end
    end

    context "when request is for the engine's own pages" do
      before do
        route_app = double("route_app", app: RailsDbInspector::Engine)
        allow(route_app).to receive(:respond_to?).with(:app).and_return(true)
        path_spec = double("path_spec", to_s: "/db_inspector(.:format)")
        route = double("route", app: route_app, path: double(spec: path_spec))
        routes = double("routes", routes: [ route ])
        app = double("rails_app", routes: routes)
        allow(Rails).to receive(:application).and_return(app)
      end

      it "does not inject widget on engine pages" do
        engine_env = env.merge("PATH_INFO" => "/db_inspector/queries")
        status, _headers, body = middleware.call(engine_env)

        expect(body.first).not_to include("rdi-widget")
      end
    end

    context "when no mount path is found" do
      before do
        routes = double("routes", routes: [])
        app = double("rails_app", routes: routes)
        allow(Rails).to receive(:application).and_return(app)
      end

      it "does not inject widget" do
        status, _headers, body = middleware.call(env)

        expect(body.first).not_to include("rdi-widget")
      end
    end

    context "when body has no </body> tag" do
      let(:inner_app) { ->(env) { [ 200, { "Content-Type" => "text/html" }, [ "<div>partial</div>" ] ] } }

      before do
        route_app = double("route_app", app: RailsDbInspector::Engine)
        allow(route_app).to receive(:respond_to?).with(:app).and_return(true)
        path_spec = double("path_spec", to_s: "/db_inspector(.:format)")
        route = double("route", app: route_app, path: double(spec: path_spec))
        routes = double("routes", routes: [ route ])
        app = double("rails_app", routes: routes)
        allow(Rails).to receive(:application).and_return(app)
      end

      it "does not inject widget when no </body> found" do
        status, _headers, body = middleware.call(env)

        expect(body.first).not_to include("rdi-widget")
      end
    end

    context "when Content-Type header is nil" do
      let(:inner_app) { ->(env) { [ 200, {}, [ "<html><body></body></html>" ] ] } }

      it "passes through without modification" do
        status, _headers, body = middleware.call(env)
        expect(body.first).not_to include("rdi-widget")
      end
    end

    it "closes response body if it responds to close" do
      closeable_body = double("body")
      allow(closeable_body).to receive(:each).and_yield("<html><body></body></html>")
      allow(closeable_body).to receive(:respond_to?).with(:close).and_return(true)
      expect(closeable_body).to receive(:close)

      app = ->(env) { [ 200, { "Content-Type" => "text/html" }, closeable_body ] }
      mw = described_class.new(app)

      routes = double("routes", routes: [])
      allow(Rails).to receive(:application).and_return(double("rails_app", routes: routes))

      mw.call(env)
    end

    context "when route.app does not respond_to?(:app)" do
      before do
        route_app = double("route_app")
        allow(route_app).to receive(:respond_to?).with(:app).and_return(false)
        path_spec = double("path_spec", to_s: "/other(.:format)")
        route = double("route", app: route_app, path: double(spec: path_spec))
        routes = double("routes", routes: [ route ])
        app = double("rails_app", routes: routes)
        allow(Rails).to receive(:application).and_return(app)
      end

      it "does not inject widget when route app has no :app method" do
        status, _headers, body = middleware.call(env)

        expect(body.first).not_to include("rdi-widget")
      end
    end

    context "when mount_path is nil and PATH_INFO starts with something" do
      before do
        routes = double("routes", routes: [])
        app = double("rails_app", routes: routes)
        allow(Rails).to receive(:application).and_return(app)
      end

      it "injectable? returns false for nil mount_path on engine's pages check" do
        # With no mount path found, the injectable? check for PATH_INFO.start_with?(mount_path) is skipped
        status, _headers, body = middleware.call(env)
        expect(body.first).not_to include("rdi-widget")
      end
    end
  end
end

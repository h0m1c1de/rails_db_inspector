# frozen_string_literal: true

module RailsDbInspector
  class DevWidgetMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, response = @app.call(env)

      # Only inject into HTML responses in development
      return [ status, headers, response ] unless injectable?(status, headers, env)

      body = +""
      response.each { |part| body << part }
      response.close if response.respond_to?(:close)

      # Find the mount path for the engine
      mount_path = find_mount_path

      if body.include?("</body>") && mount_path
        widget_html = render_widget(mount_path)
        body.sub!("</body>", "#{widget_html}\n</body>")
        headers["Content-Length"] = body.bytesize.to_s
      end

      [ status, headers, [ body ] ]
    end

    private

    def injectable?(status, headers, env)
      return false unless status == 200
      return false unless headers["Content-Type"]&.include?("text/html")

      # Don't inject into the engine's own pages
      mount_path = find_mount_path
      return false if mount_path && env["PATH_INFO"]&.start_with?(mount_path)

      true
    end

    def find_mount_path
      @mount_path ||= begin
        Rails.application.routes.routes.each do |route|
          if route.app.respond_to?(:app) && route.app.app == RailsDbInspector::Engine
            return "/" + route.path.spec.to_s.sub(/\(.*\)/, "").gsub(%r{^/|/$}, "")
          end
        end
        nil
      end
    end

    def render_widget(mount_path)
      queries_url = "#{mount_path}"
      schema_url = "#{mount_path}/schema"

      <<~HTML
        <!-- Rails DB Inspector Dev Widget -->
        <div id="rdi-widget" style="
          position: fixed;
          bottom: 16px;
          right: 16px;
          z-index: 99999;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        ">
          <div id="rdi-panel" style="
            display: none;
            background: #1f2937;
            border-radius: 12px;
            padding: 12px;
            margin-bottom: 8px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.3);
            min-width: 200px;
          ">
            <div style="color: #9ca3af; font-size: 10px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 8px; padding: 0 4px;">
              DB Inspector
            </div>
            <a href="#{queries_url}" target="_blank" rel="noopener" style="
              display: flex;
              align-items: center;
              padding: 8px 12px;
              color: #e5e7eb;
              text-decoration: none;
              font-size: 13px;
              font-weight: 500;
              border-radius: 8px;
              margin-bottom: 4px;
              transition: background 0.15s;
            " onmouseover="this.style.background='#374151'" onmouseout="this.style.background='transparent'">
              <span style="margin-right: 8px; font-size: 16px;">🔍</span>
              Query Monitor
            </a>
            <a href="#{schema_url}" target="_blank" rel="noopener" style="
              display: flex;
              align-items: center;
              padding: 8px 12px;
              color: #e5e7eb;
              text-decoration: none;
              font-size: 13px;
              font-weight: 500;
              border-radius: 8px;
              transition: background 0.15s;
            " onmouseover="this.style.background='#374151'" onmouseout="this.style.background='transparent'">
              <span style="margin-right: 8px; font-size: 16px;">🗄️</span>
              Schema Visualization
            </a>
          </div>
          <button onclick="
            var panel = document.getElementById('rdi-panel');
            panel.style.display = panel.style.display === 'none' ? 'block' : 'none';
          " style="
            width: 48px;
            height: 48px;
            border-radius: 50%;
            background: #2563eb;
            border: none;
            color: white;
            font-size: 20px;
            cursor: pointer;
            box-shadow: 0 4px 12px rgba(37, 99, 235, 0.4);
            display: flex;
            align-items: center;
            justify-content: center;
            transition: transform 0.15s, box-shadow 0.15s;
            margin-left: auto;
          " onmouseover="this.style.transform='scale(1.1)';this.style.boxShadow='0 6px 16px rgba(37,99,235,0.5)'" onmouseout="this.style.transform='scale(1)';this.style.boxShadow='0 4px 12px rgba(37,99,235,0.4)'">
            🛢️
          </button>
        </div>
        <script>
          document.addEventListener('click', function(e) {
            var widget = document.getElementById('rdi-widget');
            var panel = document.getElementById('rdi-panel');
            if (panel && widget && !widget.contains(e.target)) {
              panel.style.display = 'none';
            }
          });
        </script>
        <!-- /Rails DB Inspector Dev Widget -->
      HTML
    end
  end
end

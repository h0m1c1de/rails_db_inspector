# frozen_string_literal: true

module RailsDbInspector
  class QueriesController < ApplicationController
    include RailsDbInspector::ApplicationHelper
    
    def index
      all_queries = RailsDbInspector::QueryStore.instance.all.reverse
      @queries = all_queries
      @query_groups = group_queries_by_action(all_queries)
      @n_plus_ones = detect_n_plus_one(all_queries)
    end

    def show
      @query = RailsDbInspector::QueryStore.instance.find(params[:id])
      return head :not_found unless @query
    end

    def explain
      @query = RailsDbInspector::QueryStore.instance.find(params[:id])
      return head :not_found unless @query

      analyze = ActiveModel::Type::Boolean.new.cast(params[:analyze])

      if analyze && !RailsDbInspector.configuration.allow_explain_analyze
        return render plain: "EXPLAIN ANALYZE is disabled. Enable RailsDbInspector.configuration.allow_explain_analyze = true", status: :forbidden
      end

      explainer = RailsDbInspector::Explain.for_connection(ActiveRecord::Base.connection)
      @explain = explainer.explain(@query.sql, analyze: analyze)
    rescue RailsDbInspector::Explain::DangerousQuery => e
      render plain: e.message, status: :unprocessable_entity
    rescue RailsDbInspector::Explain::UnsupportedAdapter => e
      render plain: e.message, status: :not_implemented
    end

    def clear
      RailsDbInspector::QueryStore.instance.clear!
      redirect_to queries_path
    end
  end
end

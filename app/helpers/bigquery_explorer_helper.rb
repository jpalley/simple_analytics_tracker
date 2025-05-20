module BigqueryExplorerHelper
  def format_bigquery_value(value)
    case value
    when Hash
      content_tag(:pre, JSON.pretty_generate(value), class: 'mb-0')
    when Array
      content_tag(:pre, JSON.pretty_generate(value), class: 'mb-0')
    when Time, DateTime, ActiveSupport::TimeWithZone
      value.strftime("%Y-%m-%d %H:%M:%S UTC")
    when Date
      value.strftime("%Y-%m-%d")
    when TrueClass
      content_tag(:span, "true", class: "text-success")
    when FalseClass
      content_tag(:span, "false", class: "text-danger")
    when NilClass
      content_tag(:em, "NULL", class: "text-muted")
    else
      value.to_s
    end
  end

  def format_bigquery_type(type)
    type_classes = {
      "STRING" => "text-primary",
      "INTEGER" => "text-success",
      "FLOAT" => "text-success",
      "BOOLEAN" => "text-warning",
      "TIMESTAMP" => "text-info",
      "DATE" => "text-info",
      "DATETIME" => "text-info",
      "RECORD" => "text-secondary",
      "STRUCT" => "text-secondary"
    }

    content_tag(:code, type, class: type_classes[type] || "")
  end

  def format_bigquery_mode(mode)
    badge_classes = {
      "REQUIRED" => "bg-danger",
      "NULLABLE" => "bg-secondary",
      "REPEATED" => "bg-info"
    }

    content_tag(:span, mode, class: "badge #{badge_classes[mode] || 'bg-secondary'}")
  end
end

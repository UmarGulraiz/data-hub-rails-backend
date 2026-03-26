module GraphqlSupport
  module PayloadHelpers
    private

    def deep_camelize(value)
      case value
      when Array
        value.map { |item| deep_camelize(item) }
      when Hash
        value.each_with_object({}) do |(key, item), memo|
          memo[key.to_s.camelize(:lower)] = deep_camelize(item)
        end
      else
        value
      end
    end

    def serialize_record(record)
      deep_camelize(record.attributes)
    end

    def extract_model_attributes(raw)
      return {} if raw.blank?

      hash =
        if raw.respond_to?(:to_unsafe_h)
          raw.to_unsafe_h
        elsif raw.respond_to?(:to_h)
          raw.to_h
        else
          raw
        end
      hash.each_with_object({}) do |(key, value), memo|
        memo[key.to_s.underscore] = value
      end
    end

    def assign_filtered_attributes(record, attrs)
      attrs.each do |column, value|
        next unless record.class.column_names.include?(column.to_s)

        record[column] = normalize_attribute_value(record, column.to_s, value)
      end
    end

    def normalize_attribute_value(record, column_name, value)
      value = normalize_blank_value(record, column_name, value)
      value = normalize_array_value(record, column_name, value)
      value = normalize_enum_value(record, column_name, value)
      value
    end

    def normalize_blank_value(record, column_name, value)
      return value unless value.is_a?(String) && value.strip.empty?

      column = record.class.columns_hash[column_name]
      return value if column.nil?

      case column.type
      when :string, :text
        value
      else
        nil
      end
    end

    def normalize_enum_value(record, column_name, value)
      enum_mapping = record.class.defined_enums[column_name]
      return value if enum_mapping.blank? || value.nil?

      candidate = value.to_s
      return candidate if enum_mapping.key?(candidate) || enum_mapping.value?(candidate)

      normalized = candidate
                   .tr("-", "_")
                   .gsub(/\s+/, "_")
                   .underscore
                   .gsub(/[^a-z0-9_]/, "_")
                   .gsub(/_+/, "_")
                   .sub(/^_/, "")
                   .sub(/_$/, "")

      return normalized if enum_mapping.key?(normalized) || enum_mapping.value?(normalized)

      value
    end

    def normalize_array_value(record, column_name, value)
      column = record.class.columns_hash[column_name]
      return value if column.nil?
      return value unless column.respond_to?(:array) && column.array
      return value unless value.is_a?(String)

      value
        .split(",")
        .map { |item| item.strip }
        .reject(&:blank?)
    end
  end
end

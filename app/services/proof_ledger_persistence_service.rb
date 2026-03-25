require "securerandom"

class ProofLedgerPersistenceService
  def self.persist_from_payload!(proof_points:, current_user_id:, fallback_relation: {})
    return if proof_points.blank?

    points = proof_points.respond_to?(:to_unsafe_h) ? [proof_points.to_unsafe_h] : proof_points
    points.each do |raw_point|
      point = raw_point.respond_to?(:to_unsafe_h) ? raw_point.to_unsafe_h : raw_point.to_h
      attrs = point.transform_keys { |k| k.to_s.underscore }
      attrs = fallback_relation.merge(attrs)

      next if attrs["field_id"].blank? || attrs["proof_type"].blank?

      ProofLedger.create!(
        id: attrs["id"].presence || SecureRandom.uuid,
        investor_id: attrs["investor_id"],
        investment_vehicle_id: attrs["investment_vehicle_id"],
        investment_strategy_id: attrs["investment_strategy_id"],
        investor_contact_id: attrs["investor_contact_id"],
        investment_entity_id: attrs["investment_entity_id"],
        field_id: attrs["field_id"],
        proof_type: to_db_enum(attrs["proof_type"]),
        source_name: attrs["source_name"],
        reference: attrs["reference"],
        raw_data_url: attrs["raw_data_url"],
        data_project_id: attrs["data_project_id"],
        observed: parse_time(attrs["observed"]),
        criteria_name: attrs["criteria_name"],
        criteria_value_old: attrs["criteria_value_old"],
        criteria_value_new: attrs["criteria_value_new"],
        proof_text: attrs["proof_text"],
        certainty_score: attrs["certainty_score"],
        status: "active",
        internal_comment: attrs["internal_comment"],
        version: 0,
        rational: attrs["rational"],
        created_by_id: current_user_id,
        created_at_utc: Time.now.utc
      )
    end
  end

  def self.parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # Converts API enum names like AIResearch -> ai_research
  def self.to_db_enum(value)
    candidate = value.to_s
    return candidate if candidate.blank?

    enum_mapping = ProofLedger.proof_types
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

    compact_candidate = candidate.gsub(/[^a-z0-9]/i, "").downcase
    matched_key = enum_mapping.keys.find { |key| key.delete("_") == compact_candidate }
    return matched_key if matched_key.present?

    candidate
  end
end

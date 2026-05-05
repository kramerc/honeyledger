class Csv::ParseJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    import = Csv::Import.find_by(id: import_id)
    return if import.nil?
    return unless import.file.attached?

    parsed_count = 0
    import.file.open do |io|
      parser = Csv::Parser.new(io: io, mappings: import.column_mappings, currency: import.account.currency)
      parser.each_row do |parsed|
        record = Csv::Transaction
          .where(import_id: import.id, row_index: parsed.row_index)
          .first_or_initialize
        record.assign_attributes(
          transacted_at: parsed.transacted_at,
          posted_at: parsed.posted_at,
          description: parsed.description,
          amount_minor: parsed.amount_minor,
          raw: parsed.raw,
          synced_at: Time.current
        )
        record.save!
        parsed_count += 1
      end
    end

    import.update!(state: "parsed", parsed_at: Time.current, error: nil)
    Csv::ImportTransactionsJob.perform_later(import.id) if parsed_count.positive?
  rescue Csv::Parser::Error => e
    import&.update!(state: "failed", error: e.message)
  rescue StandardError => e
    import&.update!(state: "failed", error: "#{e.class}: #{e.message}")
    raise
  end
end
